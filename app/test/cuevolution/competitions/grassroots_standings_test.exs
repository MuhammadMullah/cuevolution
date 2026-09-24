defmodule Cuevolution.Competitions.GrassrootsStandingsTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.{Fixture, Group, MatchResult, Stage}
  alias Cuevolution.Repo

  defp stage(name), do: Repo.get_by!(Stage, name: name)

  defp group_with_players(count, name) do
    grassroots = stage("Grassroots")
    region = build(:region)
    venue = insert(:venue, region_id: region.id)

    group =
      Repo.insert!(%Group{
        stage_id: grassroots.id,
        region_id: region.id,
        venue_id: venue.id,
        category: "male",
        name: name
      })

    participants =
      for _ <- 1..count do
        participation =
          insert(:stage_participation,
            stage_id: grassroots.id,
            region_id: region.id,
            category: "male"
          )

        {:ok, _membership} = Competitions.assign_to_group(participation, group)
        participation
      end

    {group, participants, venue}
  end

  defp verified_result(group, venue, participant_a, participant_b, score) do
    round = insert(:round, stage_id: group.stage_id, group_id: group.id)

    fixture =
      insert(:fixture,
        round_id: round.id,
        participant_a_id: participant_a.id,
        participant_b_id: participant_b.id,
        venue_id: venue.id
      )

    result =
      Repo.insert!(
        MatchResult.create_changeset(%MatchResult{}, %{
          fixture_id: fixture.id,
          winner_participation_id: score["winner_id"],
          score: Map.delete(score, "winner_id"),
          recorded_by_admin_id: insert(:admin).id
        })
      )

    Repo.update!(Ecto.Changeset.change(fixture, result_id: result.id, status: "verified"))
  end

  test "Grassroots standings apply points, head-to-head, wins and frame difference" do
    a = :a
    b = :b
    c = :c

    matches = [
      %{
        participant_a_id: a,
        participant_b_id: b,
        winner_id: a,
        frames_won_a: 3,
        frames_won_b: 2,
        points_a: 3,
        points_b: 2,
        bonus_a: 0,
        bonus_b: 0
      },
      %{
        participant_a_id: b,
        participant_b_id: c,
        winner_id: b,
        frames_won_a: 4,
        frames_won_b: 1,
        points_a: 4,
        points_b: 1,
        bonus_a: 0,
        bonus_b: 0
      },
      %{
        participant_a_id: c,
        participant_b_id: a,
        winner_id: c,
        frames_won_a: 5,
        frames_won_b: 0,
        points_a: 6,
        points_b: 0,
        bonus_a: 1,
        bonus_b: 0
      }
    ]

    assert Enum.map(
             Competitions.StandingsCalculator.rank([a, b, c], matches, cascade: :points_first),
             & &1.participant_id
           ) == [c, b, a]

    tied =
      Competitions.StandingsCalculator.rank(
        [a, b],
        [
          %{
            participant_a_id: a,
            participant_b_id: b,
            winner_id: nil,
            frames_won_a: 0,
            frames_won_b: 0,
            points_a: 0,
            points_b: 0,
            bonus_a: 0,
            bonus_b: 0
          }
        ],
        cascade: :points_first
      )

    assert Enum.all?(tied, & &1.tied)

    assert Enum.map(
             Competitions.StandingsCalculator.rank(
               [a, b],
               [
                 %{
                   participant_a_id: a,
                   participant_b_id: b,
                   winner_id: nil,
                   frames_won_a: 0,
                   frames_won_b: 0,
                   points_a: 0,
                   points_b: 0,
                   bonus_a: 0,
                   bonus_b: 0
                 }
               ],
               cascade: :points_first,
               tie_breakers: [[to_string(a), to_string(b)]]
             ),
             & &1.tied
           ) == [false, false]
  end

  test "best of rest ranks candidates by points per match across uneven groups" do
    {group_a, [a1, a2, a3], venue_a} = group_with_players(3, "Best Rest A")
    {group_b, [b1, b2], venue_b} = group_with_players(2, "Best Rest B")
    config = Competitions.get_or_create_group_config(group_a.stage_id, "male")

    {:ok, _} =
      Competitions.update_group_config(config, %{advancer_count: 1, extra_qualifier_count: 1})

    verified_result(group_a, venue_a, a1, a2, %{
      "winner_id" => a1.id,
      "participant_a_frames" => 5,
      "participant_b_frames" => 0,
      "points_a" => 6,
      "points_b" => 0,
      "bonus_a" => 1,
      "bonus_b" => 0
    })

    verified_result(group_a, venue_a, a2, a3, %{
      "winner_id" => a2.id,
      "participant_a_frames" => 4,
      "participant_b_frames" => 1,
      "points_a" => 4,
      "points_b" => 1,
      "bonus_a" => 0,
      "bonus_b" => 0
    })

    verified_result(group_b, venue_b, b1, b2, %{
      "winner_id" => b1.id,
      "participant_a_frames" => 5,
      "participant_b_frames" => 0,
      "points_a" => 6,
      "points_b" => 0,
      "bonus_a" => 1,
      "bonus_b" => 0
    })

    qualifiers = Competitions.best_of_rest_qualifiers(group_a.stage_id, "male")
    a2_id = a2.id
    assert [%{participant_id: ^a2_id, points_per_match: 2.0}] = qualifiers
  end

  test "grassroots standings read verified and walkover results only" do
    {group, [a, b], venue} = group_with_players(2, "Verified Only")

    fixture =
      verified_result(group, venue, a, b, %{
        "winner_id" => a.id,
        "participant_a_frames" => 5,
        "participant_b_frames" => 0,
        "points_a" => 5,
        "points_b" => 0,
        "bonus_a" => 0,
        "bonus_b" => 0
      })

    Repo.update!(Ecto.Changeset.change(fixture, status: "walkover", walkover_kind: "single"))

    standings = Competitions.grassroots_group_standings(group)
    a_id = a.id

    assert %{participant_id: ^a_id, points: 5, bonus: 0} =
             Enum.find(standings, &(&1.participant_id == a.id))

    refute Repo.get_by(Fixture, participant_a_id: a.id, participant_b_id: b.id).status ==
             "scheduled"
  end
end
