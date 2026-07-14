defmodule CuevolutionWeb.AdminDrawsLive do
  @moduledoc """
  Admin "Draws" (fixture entry) page (spec 007) — pick a stage and round
  (or create one), batch-enter fixtures via the participant/venue live-search
  combobox, and save. Saving calls `Competitions.enter_fixtures/2`: rows
  that fail (bad participant, invalid date/time, duplicate pairing) stay in
  the scratchpad with an inline error; rows that succeed drop into the
  "Already entered" stream and dispatch a `fixture_assignment` notification
  to both participants.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Competitions
  alias Cuevolution.Teams
  alias Cuevolution.Venues
  alias CuevolutionWeb.AdminComponents

  @categories [{"Individual Male", "male"}, {"Individual Female", "female"}, {"Teams", "team"}]

  def mount(_params, _session, socket) do
    stages = Competitions.list_stages()
    stage = List.first(stages)

    {:ok,
     socket
     |> assign(
       page_title: "Draws",
       venues: Venues.list_venues(%{}),
       categories: @categories,
       stages: stages,
       stage: stage,
       rounds: Competitions.list_rounds_for_stage(stage.id),
       round: nil,
       new_round_form: to_form(%{}, as: :round),
       has_entered_fixtures: false
     )
     |> assign(:next_id, 1)
     |> assign(:rows, [blank_row(0)])
     |> stream(:entered_fixtures, [])}
  end

  def handle_event("select_stage", %{"id" => id}, socket) do
    stage = Enum.find(socket.assigns.stages, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:stage, stage)
     |> assign(:rounds, Competitions.list_rounds_for_stage(stage.id))
     |> assign(:round, nil)
     |> assign(:has_entered_fixtures, false)
     |> stream(:entered_fixtures, [], reset: true)}
  end

  def handle_event("select_round", %{"id" => id}, socket) do
    round = Enum.find(socket.assigns.rounds, &(&1.id == id))
    fixtures = Competitions.list_fixtures_for_round(round.id)

    {:noreply,
     socket
     |> assign(:round, round)
     |> assign(:has_entered_fixtures, fixtures != [])
     |> stream(:entered_fixtures, fixtures, reset: true)}
  end

  def handle_event("create_round", %{"round" => %{"name" => name}}, socket) do
    case Competitions.create_round(%{stage_id: socket.assigns.stage.id, name: name}) do
      {:ok, round} ->
        {:noreply,
         socket
         |> assign(:rounds, Competitions.list_rounds_for_stage(socket.assigns.stage.id))
         |> assign(:round, round)
         |> assign(:new_round_form, to_form(%{}, as: :round))
         |> assign(:has_entered_fixtures, false)
         |> stream(:entered_fixtures, [], reset: true)}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_round_form, to_form(changeset, as: :round))}
    end
  end

  def handle_event("add_row", _params, socket) do
    id = socket.assigns.next_id

    {:noreply,
     socket
     |> update(:rows, &(&1 ++ [blank_row(id)]))
     |> assign(:next_id, id + 1)}
  end

  def handle_event("remove_row", %{"id" => id}, socket) do
    id = String.to_integer(id)
    remaining = Enum.reject(socket.assigns.rows, &(&1.id == id))

    case remaining do
      [] ->
        new_id = socket.assigns.next_id
        {:noreply, socket |> assign(:rows, [blank_row(new_id)]) |> assign(:next_id, new_id + 1)}

      rows ->
        {:noreply, assign(socket, :rows, rows)}
    end
  end

  def handle_event("update_rows", %{"rows" => rows_params}, socket) do
    rows =
      Enum.map(socket.assigns.rows, fn row ->
        case rows_params[Integer.to_string(row.id)] do
          nil ->
            row

          params ->
            category = params["category"] || row.category

            row
            |> maybe_reset_participants(category)
            |> Map.merge(%{
              category: category,
              date: params["date"] || row.date,
              time: params["time"] || row.time,
              error: nil
            })
        end
      end)

    {:noreply, assign(socket, :rows, rows)}
  end

  # Both typing and Enter come through this one binding — see the moduledoc
  # note on `AdminComponents.field_search/1` for why a separate
  # phx-keydown/phx-key pair doesn't work here.
  def handle_event("field_keyup", %{"key" => "Enter", "row" => row_id, "field" => field}, socket) do
    row_id = String.to_integer(row_id)
    row = Enum.find(socket.assigns.rows, &(&1.id == row_id))

    case suggestions_for(row, field) do
      [top | _] ->
        {:noreply, assign(socket, :rows, apply_selection_to_rows(socket, row_id, field, top))}

      [] ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "field_keyup",
        %{"row" => row_id, "field" => field, "value" => query},
        socket
      ) do
    row_id = String.to_integer(row_id)

    rows =
      Enum.map(socket.assigns.rows, fn row ->
        if row.id == row_id do
          update_field_query(row, field, query, socket.assigns.venues)
        else
          row
        end
      end)

    {:noreply, assign(socket, :rows, rows)}
  end

  def handle_event(
        "select_field",
        %{"row" => row_id, "field" => field, "id" => id, "name" => name, "kind" => kind},
        socket
      ) do
    row_id = String.to_integer(row_id)
    suggestion = %{id: id, name: name, kind: kind}

    {:noreply, assign(socket, :rows, apply_selection_to_rows(socket, row_id, field, suggestion))}
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("save", _params, socket) do
    case socket.assigns.round do
      nil ->
        {:noreply, put_flash(socket, :error, "Select or create a round first.")}

      round ->
        attempted = Enum.reject(socket.assigns.rows, &blank_row?/1)

        if attempted == [] do
          {:noreply, put_flash(socket, :error, "Add at least one fixture row first.")}
        else
          results = Competitions.enter_fixtures(round, Enum.map(attempted, &row_to_params/1))
          {:noreply, apply_save_results(socket, attempted, results)}
        end
    end
  end

  defp apply_save_results(socket, attempted_rows, results) do
    {successes, error_rows, socket} =
      attempted_rows
      |> Enum.zip(results)
      |> Enum.reduce({0, [], socket}, fn
        {_row, {:ok, fixture}}, {count, errors, socket} ->
          {count + 1, errors, stream_insert(socket, :entered_fixtures, fixture, at: 0)}

        {row, {:error, reason}}, {count, errors, socket} ->
          {count, errors ++ [%{row | error: format_row_error(reason)}], socket}
      end)

    untouched = Enum.filter(socket.assigns.rows, &blank_row?/1)
    kept_rows = error_rows ++ untouched
    {rows, next_id} = ensure_at_least_one_row(kept_rows, socket.assigns.next_id)

    socket
    |> assign(:rows, rows)
    |> assign(:next_id, next_id)
    |> assign(:has_entered_fixtures, socket.assigns.has_entered_fixtures or successes > 0)
    |> flash_save_summary(successes, error_rows)
  end

  defp ensure_at_least_one_row([], next_id), do: {[blank_row(next_id)], next_id + 1}
  defp ensure_at_least_one_row(rows, next_id), do: {rows, next_id}

  defp flash_save_summary(socket, successes, []) when successes > 0 do
    put_flash(
      socket,
      :info,
      "Saved #{successes} fixture#{if successes == 1, do: "", else: "s"} and notified players."
    )
  end

  defp flash_save_summary(socket, 0, _error_rows) do
    put_flash(socket, :error, "Couldn't save — see the row error(s) below.")
  end

  defp flash_save_summary(socket, successes, error_rows) do
    put_flash(
      socket,
      :info,
      "Saved #{successes} fixture#{if successes == 1, do: "", else: "s"}; #{length(error_rows)} row(s) had errors — see below."
    )
  end

  defp row_to_params(row) do
    %{
      "category" => row.category,
      "a_kind" => row.a_kind,
      "a_id" => row.a_id,
      "b_kind" => row.b_kind,
      "b_id" => row.b_id,
      "venue_id" => row.venue_id,
      "date" => row.date,
      "time" => row.time
    }
  end

  defp format_row_error(:invalid_datetime), do: "Enter a valid date and time."
  defp format_row_error(:participant_required), do: "Select both participants."

  defp format_row_error({:participant_a, :participant_not_in_stage}),
    do: "Participant A isn't registered for this stage/category."

  defp format_row_error({:participant_a, :participant_required}), do: "Select participant A."

  defp format_row_error({:participant_b, :participant_not_in_stage}),
    do: "Participant B isn't registered for this stage/category."

  defp format_row_error({:participant_b, :participant_required}), do: "Select participant B."

  defp format_row_error(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
  end

  defp format_row_error(_other), do: "Couldn't save this row."

  defp blank_row?(row) do
    is_nil(row.a_id) and is_nil(row.b_id) and is_nil(row.venue_id) and row.date == "" and
      row.time == ""
  end

  defp apply_selection_to_rows(socket, row_id, field, suggestion) do
    Enum.map(socket.assigns.rows, fn row ->
      if row.id == row_id, do: apply_selection(row, field, suggestion), else: row
    end)
  end

  defp suggestions_for(row, "a"), do: row.a_suggestions
  defp suggestions_for(row, "b"), do: row.b_suggestions
  defp suggestions_for(row, "venue"), do: row.venue_suggestions

  defp apply_selection(row, "a", s),
    do: %{row | a: s.name, a_id: s.id, a_kind: s.kind, a_suggestions: [], error: nil}

  defp apply_selection(row, "b", s),
    do: %{row | b: s.name, b_id: s.id, b_kind: s.kind, b_suggestions: [], error: nil}

  defp apply_selection(row, "venue", s),
    do: %{row | venue: s.name, venue_id: s.id, venue_suggestions: [], error: nil}

  defp update_field_query(row, "a", query, _venues),
    do: %{
      row
      | a: query,
        a_id: nil,
        a_kind: nil,
        a_suggestions: participant_suggestions(row.category, query),
        error: nil
    }

  defp update_field_query(row, "b", query, _venues),
    do: %{
      row
      | b: query,
        b_id: nil,
        b_kind: nil,
        b_suggestions: participant_suggestions(row.category, query),
        error: nil
    }

  defp update_field_query(row, "venue", query, venues),
    do: %{
      row
      | venue: query,
        venue_id: nil,
        venue_suggestions: venue_suggestions(venues, query),
        error: nil
    }

  defp participant_suggestions(_category, ""), do: []

  defp participant_suggestions(category, query) when category in ["male", "female"] do
    category |> Accounts.search_players(query) |> Enum.map(&player_suggestion/1)
  end

  defp participant_suggestions("team", query) do
    %{name: query} |> Teams.list_teams_filtered() |> Enum.take(6) |> Enum.map(&team_suggestion/1)
  end

  defp venue_suggestions(_venues, ""), do: []

  defp venue_suggestions(venues, query) do
    needle = String.downcase(query)

    venues
    |> Enum.filter(&String.contains?(String.downcase(&1.name), needle))
    |> Enum.take(6)
    |> Enum.map(&venue_suggestion/1)
  end

  defp player_suggestion(player) do
    %{
      id: player.id,
      kind: "player",
      name: "#{player.first_name} #{player.last_name}",
      sub: "@#{player.username}"
    }
  end

  defp team_suggestion(team) do
    %{
      id: team.id,
      kind: "team",
      name: team.name,
      sub: "#{team.region.name} · #{length(team.roster)} on roster"
    }
  end

  defp venue_suggestion(venue) do
    %{id: venue.id, kind: "venue", name: venue.name, sub: venue.region.name}
  end

  defp maybe_reset_participants(row, category) when category == row.category, do: row

  defp maybe_reset_participants(row, _new_category) do
    %{
      row
      | a: "",
        a_id: nil,
        a_kind: nil,
        a_suggestions: [],
        b: "",
        b_id: nil,
        b_kind: nil,
        b_suggestions: []
    }
  end

  defp blank_row(id) do
    %{
      id: id,
      category: "male",
      a: "",
      a_id: nil,
      a_kind: nil,
      a_suggestions: [],
      b: "",
      b_id: nil,
      b_kind: nil,
      b_suggestions: [],
      venue_id: nil,
      venue: "",
      venue_suggestions: [],
      date: "",
      time: "",
      error: nil
    }
  end

  defp fixture_time_label(fixture) do
    eat = Competitions.fixture_time_in_eat(fixture)
    Calendar.strftime(eat, "%b %-d, %Y · %H:%M")
  end
end
