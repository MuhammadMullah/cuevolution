defmodule Cuevolution.Competitions.Workers.DispatchDrawPublishedNotifications do
  @moduledoc """
  Dispatches one consolidated published-draw notification per recipient.

  Individual (male/female) fixtures notify both players. Team-category
  fixtures notify only each side's **captain** — not the rest of the
  roster — since the captain is the one who manages the team's match
  logistics; `Notifications.dispatch/3` only accepts a `%Player{}`, so a
  team's "recipient" for this purpose is always its captain.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:draw_id]]

  import Ecto.Query

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Competitions.{Fixture, Group, GroupMembership, Round, StageParticipation}
  alias Cuevolution.Notifications
  alias Cuevolution.Repo
  alias Cuevolution.Teams.Team

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"draw_id" => draw_id}}) do
    entries =
      draw_id
      |> notifications_by_recipient()
      |> Enum.map(fn {player, fixtures} ->
        {player, %{fixtures: fixtures}, "draw_published:#{draw_id}:#{player.id}"}
      end)

    Notifications.dispatch_many(entries, :draw_published)
  end

  # A draw's groups are always a single category (male, female, or team),
  # so exactly one of these two queries ever returns rows for a given
  # `draw_id` — both run unconditionally rather than branching on the
  # draw's category, to keep this self-contained.
  defp notifications_by_recipient(draw_id) do
    %{}
    |> accumulate(individual_fixtures(draw_id), &individual_payloads/1)
    |> accumulate(team_fixtures(draw_id), &team_payloads/1)
    |> Map.values()
  end

  defp accumulate(acc, rows, payloads_fn) do
    Enum.reduce(rows, acc, fn row, acc ->
      Enum.reduce(payloads_fn.(row), acc, &add_payload/2)
    end)
  end

  defp add_payload({recipient, payload}, acc) do
    Map.update(acc, recipient.id, {recipient, [payload]}, fn {player, rows} ->
      {player, rows ++ [payload]}
    end)
  end

  defp individual_payloads(%{player_a: player_a, player_b: player_b} = fixture) do
    [
      {player_a, fixture_payload(fixture, "#{player_b.first_name} #{player_b.last_name}")},
      {player_b, fixture_payload(fixture, "#{player_a.first_name} #{player_a.last_name}")}
    ]
  end

  defp team_payloads(%{captain_a: captain_a, captain_b: captain_b} = fixture) do
    [
      {captain_a, fixture_payload(fixture, fixture.team_b_name)},
      {captain_b, fixture_payload(fixture, fixture.team_a_name)}
    ]
  end

  defp individual_fixtures(draw_id) do
    from(f in Fixture,
      join: r in Round,
      on: r.id == f.round_id,
      join: g in Group,
      on: g.id == r.group_id,
      join: gm_a in GroupMembership,
      on: gm_a.stage_participation_id == f.participant_a_id and gm_a.group_id == g.id,
      join: gm_b in GroupMembership,
      on: gm_b.stage_participation_id == f.participant_b_id and gm_b.group_id == g.id,
      join: pa in StageParticipation,
      on: pa.id == f.participant_a_id,
      join: pb in StageParticipation,
      on: pb.id == f.participant_b_id,
      join: player_a in Player,
      on: player_a.id == pa.player_id,
      join: player_b in Player,
      on: player_b.id == pb.player_id,
      where: g.draw_id == ^draw_id,
      order_by: [asc: f.match_id],
      select: %{
        match_id: f.match_id,
        round: r.name,
        player_a: player_a,
        player_b: player_b
      }
    )
    |> Repo.all()
  end

  defp team_fixtures(draw_id) do
    from(f in Fixture,
      join: r in Round,
      on: r.id == f.round_id,
      join: g in Group,
      on: g.id == r.group_id,
      join: gm_a in GroupMembership,
      on: gm_a.stage_participation_id == f.participant_a_id and gm_a.group_id == g.id,
      join: gm_b in GroupMembership,
      on: gm_b.stage_participation_id == f.participant_b_id and gm_b.group_id == g.id,
      join: pa in StageParticipation,
      on: pa.id == f.participant_a_id,
      join: pb in StageParticipation,
      on: pb.id == f.participant_b_id,
      join: team_a in Team,
      on: team_a.id == pa.team_id,
      join: team_b in Team,
      on: team_b.id == pb.team_id,
      join: captain_a in Player,
      on: captain_a.id == team_a.captain_id,
      join: captain_b in Player,
      on: captain_b.id == team_b.captain_id,
      where: g.draw_id == ^draw_id,
      order_by: [asc: f.match_id],
      select: %{
        match_id: f.match_id,
        round: r.name,
        captain_a: captain_a,
        captain_b: captain_b,
        team_a_name: team_a.name,
        team_b_name: team_b.name
      }
    )
    |> Repo.all()
  end

  defp fixture_payload(fixture, opponent_name) do
    %{match_id: fixture.match_id, round: fixture.round, opponent_name: opponent_name}
  end
end
