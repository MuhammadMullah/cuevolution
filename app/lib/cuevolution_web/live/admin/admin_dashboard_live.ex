defmodule CuevolutionWeb.AdminDashboardLive do
  @moduledoc """
  Admin dashboard — stat tiles and "needs attention" are backed by real
  `Accounts`/`Teams`/`Notifications`/`Competitions` data. Dashboard charts
  are serialized as small datasets for the ECharts LiveView hook.
  """
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.StageParticipation
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Repo
  alias Cuevolution.Teams.Team
  alias CuevolutionWeb.AdminComponents

  @week_seconds 7 * 24 * 60 * 60

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Dashboard",
       stat_tiles: stat_tiles(),
       region_chart: region_chart(),
       registration_chart: registration_chart(),
       category_chart: category_chart(),
       pipeline_bars: pipeline_bars(),
       attention_items: attention_items()
     )}
  end

  defp stat_tiles do
    week_ago = DateTime.add(DateTime.utc_now(), -@week_seconds, :second)

    players_total = Repo.aggregate(active_players_query(), :count)

    players_this_week =
      Repo.aggregate(active_players_query() |> where([p], p.inserted_at >= ^week_ago), :count)

    teams_total = Repo.aggregate(Team, :count)
    teams_this_week = Repo.aggregate(from(t in Team, where: t.inserted_at >= ^week_ago), :count)

    regions_total = Repo.aggregate(from(r in Cuevolution.Accounts.Region), :count)

    [
      %{
        label: "Registered players",
        value: to_string(players_total),
        delta: week_delta(players_this_week),
        delta_class: "text-green-600"
      },
      %{
        label: "Active teams",
        value: to_string(teams_total),
        delta: week_delta(teams_this_week),
        delta_class: "text-green-600"
      },
      %{
        label: "Regions",
        value: to_string(regions_total),
        delta: nil,
        delta_class: "text-ink-500"
      },
      %{
        label: "Fixtures this week",
        value: to_string(fixtures_this_week()),
        delta: "scheduled in the next 7 days",
        delta_class: "text-ink-500"
      },
      %{
        label: "Pending results",
        value: to_string(pending_results()),
        delta: "fixtures awaiting entry",
        delta_class: "text-ink-500"
      }
    ]
  end

  defp week_delta(0), do: nil
  defp week_delta(count), do: "+#{count} this week"

  defp active_players_query, do: from(p in Player, where: is_nil(p.anonymized_at))

  defp fixtures_this_week do
    now = DateTime.utc_now()
    next_week = DateTime.add(now, @week_seconds, :second)

    Repo.aggregate(
      from(f in Fixture,
        where: f.scheduled_at >= ^now and f.scheduled_at < ^next_week
      ),
      :count
    )
  end

  defp pending_results do
    Repo.aggregate(from(f in Fixture, where: is_nil(f.result_id)), :count)
  end

  defp region_chart do
    player_rows =
      Repo.all(
        from p in Player,
          join: r in assoc(p, :region),
          where: is_nil(p.anonymized_at) and is_nil(p.team_id),
          group_by: [r.name, p.gender],
          select: {r.name, p.gender, count(p.id)}
      )

    team_rows =
      Repo.all(
        from p in Player,
          join: r in assoc(p, :region),
          where: not is_nil(p.team_id) and is_nil(p.anonymized_at),
          group_by: r.name,
          select: {r.name, count(p.id)}
      )

    regions =
      Accounts.list_regions()
      |> Enum.map(fn region ->
        male = count_for(player_rows, region.name, "male")
        female = count_for(player_rows, region.name, "female")
        teams = count_for(team_rows, region.name)
        total = male + female + teams

        %{
          id: region.id,
          name: region.name,
          male: male,
          female: female,
          teams: teams,
          total: total
        }
      end)
      |> Enum.sort_by(& &1.total, :desc)

    %{regions: regions}
  end

  defp count_for(rows, region, category) do
    case Enum.find(rows, fn {row_region, row_category, _count} ->
           row_region == region and row_category == category
         end) do
      {_, _, count} -> count
      nil -> 0
    end
  end

  defp count_for(rows, region) do
    case Enum.find(rows, fn {row_region, _count} -> row_region == region end) do
      {_, count} -> count
      nil -> 0
    end
  end

  defp registration_chart do
    now = DateTime.utc_now()
    today = DateTime.to_date(now)
    first_day = Date.beginning_of_month(today)
    day_count = Date.diff(today, first_day) + 1
    start_at = NaiveDateTime.new!(first_day, ~T[00:00:00])

    labels =
      Enum.map(0..(day_count - 1), fn index ->
        Date.add(first_day, index) |> Calendar.strftime("%d %b")
      end)

    values =
      Repo.all(from p in Player, where: p.inserted_at >= ^start_at, select: p.inserted_at)
      |> Enum.reduce(List.duplicate(0, day_count), fn inserted_at, counts ->
        day_index = Date.diff(NaiveDateTime.to_date(inserted_at), first_day)
        List.update_at(counts, day_index, &(&1 + 1))
      end)

    %{labels: labels, values: values}
  end

  defp category_chart do
    [
      %{
        name: "Individual male",
        value:
          Repo.aggregate(
            from(
              p in Player,
              where: p.gender == "male" and is_nil(p.anonymized_at) and is_nil(p.team_id)
            ),
            :count
          )
      },
      %{
        name: "Individual female",
        value:
          Repo.aggregate(
            from(
              p in Player,
              where: p.gender == "female" and is_nil(p.anonymized_at) and is_nil(p.team_id)
            ),
            :count
          )
      },
      %{
        name: "Team players",
        value:
          Repo.aggregate(
            from(p in Player, where: not is_nil(p.team_id) and is_nil(p.anonymized_at)),
            :count
          )
      }
    ]
  end

  defp pipeline_bars do
    rows =
      Repo.all(
        from p in StageParticipation,
          join: s in assoc(p, :stage),
          group_by: [s.name, s.order],
          order_by: s.order,
          select: {s.name, count(p.id)}
      )

    total = Enum.reduce(rows, 0, fn {_, count}, sum -> sum + count end)

    colors = %{
      "Grassroots" => "#189A63",
      "Regional" => "#5761B4",
      "Circuit" => "#D9A02B",
      "Finals" => "#0D0C22"
    }

    Enum.map(rows, fn {name, count} ->
      %{
        label: name,
        count: count,
        pct: if(total == 0, do: "0%", else: "#{round(count / total * 100)}%"),
        color: Map.get(colors, name, "#E32219")
      }
    end)
  end

  defp attention_items do
    []
    |> maybe_add_failed_notifications()
    |> maybe_add_custom_venue_submissions()
  end

  defp maybe_add_failed_notifications(items) do
    case Repo.aggregate(from(n in Notification, where: n.status == "failed"), :count) do
      0 ->
        items

      count ->
        items ++
          [
            %{
              icon: "✉",
              title: "#{count} notification #{pluralize(count, "delivery", "deliveries")} failed",
              sub: "Review in the Notification Log"
            }
          ]
    end
  end

  defp maybe_add_custom_venue_submissions(items) do
    query =
      from p in Player, where: not is_nil(p.other_venue_name) and p.other_venue_name != ""

    case Repo.aggregate(query, :count) do
      0 ->
        items

      count ->
        items ++
          [
            %{
              icon: "◆",
              title:
                "#{count} custom venue #{pluralize(count, "submission", "submissions")} pending",
              sub: "Review under Venue Management"
            }
          ]
    end
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural
end
