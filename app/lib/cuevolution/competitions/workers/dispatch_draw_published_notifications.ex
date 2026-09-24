defmodule Cuevolution.Competitions.Workers.DispatchDrawPublishedNotifications do
  @moduledoc "Dispatches one consolidated published-draw notification per player."

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    unique: [period: :infinity, keys: [:draw_id]]

  import Ecto.Query

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Competitions.{Fixture, Group, GroupMembership, Round, StageParticipation}
  alias Cuevolution.Notifications
  alias Cuevolution.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"draw_id" => draw_id}}) do
    draw_id
    |> fixtures_for_draw()
    |> notifications_by_player()
    |> Enum.each(fn {player, fixtures} ->
      Notifications.dispatch(
        player,
        :draw_published,
        %{fixtures: fixtures},
        idempotency_key: "draw_published:#{draw_id}:#{player.id}"
      )
    end)

    :ok
  end

  defp fixtures_for_draw(draw_id) do
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
        player_a_id: player_a.id,
        player_b_id: player_b.id,
        player_a: player_a,
        player_b: player_b
      }
    )
    |> Repo.all()
  end

  defp notifications_by_player(fixtures) do
    Enum.reduce(fixtures, %{}, fn %{player_a: player_a, player_b: player_b} = fixture, acc ->
      acc
      |> Map.update(player_a.id, {player_a, [fixture_payload(fixture, player_b)]}, fn {player,
                                                                                       rows} ->
        {player, rows ++ [fixture_payload(fixture, player_b)]}
      end)
      |> Map.update(player_b.id, {player_b, [fixture_payload(fixture, player_a)]}, fn {player,
                                                                                       rows} ->
        {player, rows ++ [fixture_payload(fixture, player_a)]}
      end)
    end)
    |> Map.values()
  end

  defp fixture_payload(fixture, opponent) do
    %{
      match_id: fixture.match_id,
      round: fixture.round,
      opponent_name: "#{opponent.first_name} #{opponent.last_name}"
    }
  end
end
