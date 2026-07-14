defmodule CuevolutionWeb.AdminDashboardLive do
  @moduledoc """
  Admin dashboard — stat tiles and "needs attention" are backed by real
  `Accounts`/`Teams`/`Notifications` data. "Fixtures this week", "Pending
  results", and the stage pipeline chart stay honestly empty until
  `Cuevolution.Competitions` (draws/results, specs 006-009) exists — see
  `AdminDrawsLive`/`AdminResultsLive` for the same deferral.
  """
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Notifications.Notification
  alias Cuevolution.Repo
  alias Cuevolution.Teams.Team
  alias CuevolutionWeb.AdminComponents

  @week_seconds 7 * 24 * 60 * 60
  @day_seconds 24 * 60 * 60

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Dashboard",
       stat_tiles: stat_tiles(),
       attention_items: attention_items(),
       pipeline_bars: []
     )}
  end

  defp stat_tiles do
    week_ago = DateTime.add(DateTime.utc_now(), -@week_seconds, :second)
    day_ago = DateTime.add(DateTime.utc_now(), -@day_seconds, :second)

    players_total = Repo.aggregate(active_players_query(), :count)

    players_this_week =
      Repo.aggregate(active_players_query() |> where([p], p.inserted_at >= ^week_ago), :count)

    teams_total = Repo.aggregate(Team, :count)
    teams_this_week = Repo.aggregate(from(t in Team, where: t.inserted_at >= ^week_ago), :count)

    regions_total = length(Accounts.list_regions())

    notifications_sent_total =
      Repo.aggregate(from(n in Notification, where: n.status == "sent"), :count)

    notifications_sent_24h =
      Repo.aggregate(
        from(n in Notification, where: n.status == "sent" and n.inserted_at >= ^day_ago),
        :count
      )

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
        value: "—",
        delta: "Draws aren't wired up yet",
        delta_class: "text-ink-500"
      },
      %{
        label: "Pending results",
        value: "—",
        delta: "Results aren't wired up yet",
        delta_class: "text-ink-500"
      },
      %{
        label: "Notifications sent",
        value: to_string(notifications_sent_total),
        delta: "#{notifications_sent_24h} in the last 24h",
        delta_class: "text-ink-500"
      }
    ]
  end

  defp week_delta(0), do: nil
  defp week_delta(count), do: "+#{count} this week"

  defp active_players_query, do: from(p in Player, where: is_nil(p.anonymized_at))

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
