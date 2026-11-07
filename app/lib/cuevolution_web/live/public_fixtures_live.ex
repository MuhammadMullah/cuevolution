defmodule CuevolutionWeb.PublicFixturesLive do
  @moduledoc """
  Every fixture in the competition, by category — `/matches`.

  The public counterpart of the tournament director's list view. `/live`
  answers "what is happening now", capped to what fits on a screen; this
  answers "when do I play, and who against" by showing the whole draw, round
  by round, with the same match numbers the director sees so a player and an
  official are talking about the same M113.

  Read-only and unauthenticated, and the category and filter are both in the
  URL so a particular view can be linked to. Each card opens that match's own
  page.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Competitions
  alias CuevolutionWeb.BracketComponents
  alias CuevolutionWeb.StandingsRefresh

  @tabs [{"male", "Individual Male"}, {"female", "Individual Female"}, {"team", "Teams"}]
  @filters ~w(all live next finished)
  @views ~w(list chart)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Cuevolution.PubSub, "standings")

    {:ok,
     socket
     |> assign(page_title: "Fixtures", tabs: @tabs, fit: true)
     |> StandingsRefresh.init()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    category = if params["category"] in ~w(male female team), do: params["category"], else: "male"
    filter = if params["filter"] in @filters, do: params["filter"], else: "all"
    # The team event is a round robin — there is no bracket to chart.
    view = if params["view"] in @views and category != "team", do: params["view"], else: "list"

    {:noreply, socket |> assign(category: category, filter: filter, view: view) |> load()}
  end

  @impl true
  def handle_event("switch", %{"category" => category}, socket) do
    {:noreply, push_patch(socket, to: path_for(category, "all", "list"))}
  end

  def handle_event("switch", %{"filter" => filter}, socket) do
    {:noreply,
     push_patch(socket, to: path_for(socket.assigns.category, filter, socket.assigns.view))}
  end

  def handle_event("switch", %{"view" => view}, socket) do
    {:noreply,
     push_patch(socket, to: path_for(socket.assigns.category, socket.assigns.filter, view))}
  end

  # Fit scales the two-sided knockout to the screen; 100% shows it at full
  # size, scrolling sideways, for reading names on a small screen.
  def handle_event("fit", %{"fit" => fit}, socket) do
    {:noreply, assign(socket, fit: fit == "true")}
  end

  @impl true
  def handle_info({:points_updated, _id}, socket) do
    {:noreply, StandingsRefresh.refresh(socket, &load/1)}
  end

  def handle_info(:refresh_standings, socket) do
    {:noreply, StandingsRefresh.refreshed(socket, &load/1)}
  end

  defp path_for(category, filter, view) do
    query =
      [{"category", category}, {"filter", filter}, {"view", view}]
      |> Enum.reject(fn {_k, v} -> v in ["all", "list"] end)
      |> Map.new()

    ~p"/matches?#{query}"
  end

  # Everything is presented here rather than in the template: a `<% x = ... %>`
  # in HEEx defeats change tracking for its whole block, and this page reloads
  # itself as frames land.
  defp load(socket) do
    fixtures = Competitions.public_fixtures(socket.assigns.category)
    numbers = match_numbers(fixtures)

    rows = Enum.map(fixtures, &present(&1, numbers))
    shown = Enum.filter(rows, &matches_filter?(&1, socket.assigns.filter))

    assign(socket,
      counts: counts(rows),
      total: length(rows),
      played: Enum.count(rows, &(&1.state in [:final, :walkover, :bye])),
      live_now: Enum.count(rows, &(&1.state == :live)),
      chartable?: Enum.any?(rows, &(&1.bracket_side in ["winners", "losers", "knockout"])),
      rounds: group_rounds(rows, shown),
      # The chart always shows the whole bracket: a half-drawn bracket is not
      # a bracket, so the status filter belongs to the list view only.
      lanes: if(socket.assigns.view == "chart", do: build_lanes(rows), else: [])
    )
  end

  # ------------------------------------------------------------------ chart

  @lane_titles [
    {"Winners' side", "winners"},
    {"Losers' side", "losers"},
    {"Knockout", "knockout"}
  ]

  defp build_lanes(rows) do
    first_knockout =
      rows
      |> Enum.filter(&(&1.bracket_side == "knockout"))
      |> Enum.map(& &1.round_sequence)
      |> Enum.min(fn -> nil end)

    @lane_titles
    |> Enum.map(fn {title, side} ->
      lane_rounds =
        rows
        |> Enum.filter(&(&1.bracket_side == side))
        |> Enum.chunk_by(& &1.round_sequence)
        |> Enum.map(fn [first | _] = matches ->
          %{
            name: first.round_name,
            race_to: first.race_to,
            shade_a?: shade_a?(first, first_knockout),
            matches: matches
          }
        end)

      BracketComponents.build_lane(title, side, lane_rounds, :matches)
    end)
    |> Enum.reject(&(&1.rounds == []))
  end

  # Slot A holds whoever came down from the winners' side: on a crossover
  # round, and on the round where the two halves first meet. Keyed on the
  # round code, not its name — under the current format L2 *and* L4 are
  # crossovers, and only the code says so reliably.
  defp shade_a?(%{bracket_side: "losers", round_code: "L" <> n}, _first_knockout) do
    match?({i, ""} when rem(i, 2) == 0, Integer.parse(n))
  end

  defp shade_a?(%{bracket_side: "knockout", round_sequence: seq}, first_knockout),
    do: seq == first_knockout

  defp shade_a?(_row, _first_knockout), do: false

  # Numbered across the whole draw in play order, so the numbers do not move
  # when a filter is applied.
  defp match_numbers(fixtures) do
    fixtures |> Enum.with_index(1) |> Map.new(fn {f, n} -> {f.id, "M#{n}"} end)
  end

  defp counts(rows) do
    %{
      all: length(rows),
      live: Enum.count(rows, &(&1.state == :live)),
      next: Enum.count(rows, &(&1.state in [:upcoming, :waiting])),
      finished: Enum.count(rows, &(&1.state in [:final, :walkover, :bye]))
    }
  end

  defp matches_filter?(_row, "all"), do: true
  defp matches_filter?(row, "live"), do: row.state == :live
  defp matches_filter?(row, "next"), do: row.state in [:upcoming, :waiting]
  defp matches_filter?(row, "finished"), do: row.state in [:final, :walkover, :bye]

  # Rounds keep their full played-count even when the filter hides some of
  # their matches — "3 of 64 played" is about the round, not about the view.
  defp group_rounds(all_rows, shown) do
    totals = Enum.group_by(all_rows, & &1.round_key)

    shown
    |> Enum.chunk_by(& &1.round_key)
    |> Enum.map(fn [first | _] = chunk ->
      in_round = Map.fetch!(totals, first.round_key)

      %{
        heading: first.round_heading,
        race_to: first.race_to,
        played: Enum.count(in_round, &(&1.state in [:final, :walkover, :bye])),
        total: length(in_round),
        fixtures: chunk
      }
    end)
  end

  defp present(row, numbers) do
    state = state(row)

    %{
      number: Map.get(numbers, row.id, "—"),
      match_id: row.match_id,
      bracket_side: row.bracket_side,
      round_code: row.round_code,
      round_name: row.round_name,
      round_sequence: row.round_sequence,
      round_key: {row.round_sequence, row.group_name},
      round_heading: round_heading(row),
      race_to: row.race_to,
      state: state,
      state_label: state_label(state),
      a: side(row, :a),
      b: side(row, :b),
      a_score: score(row, "a"),
      b_score: score(row, "b"),
      a_won: won?(row, :a),
      b_won: won?(row, :b),
      start: start_label(row, state),
      loser_to: loser_destination(row, numbers)
    }
  end

  defp round_heading(%{group_name: nil} = row), do: row.round_name
  defp round_heading(row), do: "#{row.group_name} · #{row.round_name}"

  defp side(row, :a), do: row.a_player || row.a_team
  defp side(row, :b), do: row.b_player || row.b_team

  defp score(%{bye: true}, _side), do: nil
  defp score(%{score: %{} = final}, side), do: frames(final, side)
  defp score(%{live_score: %{} = live}, side), do: frames(live, side)
  defp score(_row, _side), do: nil

  defp frames(score, side) do
    Map.get(score, side) ||
      Map.get(score, if(side == "a", do: "participant_a_frames", else: "participant_b_frames"))
  end

  defp won?(%{winner_id: id} = row, :a) when is_binary(id), do: row.a_id == id
  defp won?(%{winner_id: id} = row, :b) when is_binary(id), do: row.b_id == id
  defp won?(_row, _side), do: false

  defp state(%{bye: true}), do: :bye
  defp state(%{status: s}) when s in ["completed", "verified"], do: :final
  defp state(%{status: "walkover"}), do: :walkover
  defp state(%{status: "live"}), do: :live
  defp state(%{a_id: nil}), do: :waiting
  defp state(%{b_id: nil}), do: :waiting
  defp state(_row), do: :upcoming

  defp state_label(:bye), do: "Bye"
  defp state_label(:final), do: "Decided"
  defp state_label(:walkover), do: "Walkover"
  defp state_label(:live), do: "In play"
  defp state_label(:waiting), do: "Waiting"
  defp state_label(:upcoming), do: "Up next"

  # A match with no time yet says so, rather than showing nothing at all —
  # "when do I play" is the question this page exists to answer, and a blank
  # reads as an oversight rather than as "not decided yet".
  #
  # A bye is the exception: nobody plays it, so there is no time to set and
  # "TBD" would be a promise that never arrives.
  defp start_label(_row, :bye), do: nil
  defp start_label(%{scheduled_at: nil}, _state), do: "TBD"

  defp start_label(row, _state) do
    row.scheduled_at |> Competitions.to_eat() |> Calendar.strftime("%a %-d %b, %H:%M")
  end

  # Where this match's loser goes — the thing that makes a double-elimination
  # sheet readable. A round-robin fixture has no such route.
  defp loser_destination(%{loser_to_fixture_id: nil}, _numbers), do: nil

  defp loser_destination(%{loser_to_fixture_id: id}, numbers) do
    case Map.get(numbers, id) do
      nil -> nil
      number -> "Loser to #{number}"
    end
  end
end
