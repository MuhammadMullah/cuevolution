defmodule Cuevolution.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Cuevolution.Repo

  import Ecto.Query

  alias Cuevolution.Accounts.{Admin, Player, Region}

  alias Cuevolution.Competitions.{
    CuevoPointsEntry,
    Fixture,
    Group,
    GroupMembership,
    KnockoutBracket,
    MatchFrame,
    MatchResult,
    Round,
    Stage,
    StageCapacityConfig,
    StageParticipation
  }

  alias Cuevolution.Teams.Team
  alias Cuevolution.Venues.Venue

  def region_factory do
    regions = Cuevolution.Repo.all(from r in Region, order_by: r.slug)
    index = sequence(:region_cycle, & &1)
    Enum.at(regions, rem(index, length(regions)))
  end

  def admin_factory do
    %Admin{
      email: sequence(:email, &"admin-#{&1}@cuevolution.test"),
      hashed_password: Bcrypt.hash_pwd_salt("Valid1!Pass")
    }
  end

  def player_factory do
    region = build(:region)

    %Player{
      first_name: sequence(:first_name, &"Player#{&1}"),
      last_name: "Test",
      date_of_birth: Date.add(Date.utc_today(), -365 * 20),
      gender: Enum.random(["male", "female"]),
      email: sequence(:email, &"player-#{&1}@cuevolution.test"),
      mobile_number:
        sequence(:mobile_number, &"+2547#{String.pad_leading(to_string(&1), 8, "0")}"),
      location: "Nairobi",
      username: sequence(:username, &"player#{&1}"),
      notification_preference: "email",
      hashed_password: Bcrypt.hash_pwd_salt("Valid1!Pass"),
      region_id: region.id
    }
  end

  def venue_factory do
    region = build(:region)

    %Venue{
      name: sequence(:venue_name, &"Venue #{&1}"),
      active: true,
      region_id: region.id
    }
  end

  # Builds a team with a real, persisted captain. Note the captain's own
  # `team_id` isn't back-filled here — that bidirectional link is a job for
  # `Teams.create_team/2` (captain + roster consistency is exactly what that
  # function's Multi guarantees). Tests that need a fully roster-consistent
  # team should go through `Teams.create_team/2`, not this shortcut.
  def team_factory do
    captain = insert(:player)

    %Team{
      name: sequence(:team_name, &"Team #{&1}"),
      region_id: captain.region_id,
      captain_id: captain.id
    }
  end

  @doc "Cycles through the 4 seeded stages (Grassroots/Regional/Circuit/Finals), same fixed-domain pattern as `region_factory/0`."
  def stage_factory do
    stages = Cuevolution.Repo.all(from s in Stage, order_by: s.order)
    index = sequence(:stage_cycle, & &1)
    Enum.at(stages, rem(index, length(stages)))
  end

  @doc """
  Cycles through the 6 open-stage/category combos (Grassroots+Regional ×
  male/female/team) that have no seeded config row — Circuit/Finals are
  already seeded by the migration (spec 006 FR-005/FR-006), so building
  against those would collide with the `[:stage_id, :category]` unique
  index. Only good for 6 inserts before it starts repeating combos.
  """
  def stage_capacity_config_factory do
    open_stages =
      Cuevolution.Repo.all(from s in Stage, where: s.order in [1, 2], order_by: s.order)

    combos = for s <- open_stages, category <- ~w(male female team), do: {s, category}
    index = sequence(:stage_capacity_config_cycle, & &1)
    {stage, category} = Enum.at(combos, rem(index, length(combos)))

    %StageCapacityConfig{
      stage_id: stage.id,
      category: category,
      capacity_limit: 32,
      current_count: 0
    }
  end

  @doc "Defaults to an individual (player) participation. For a team-category participation, override explicitly: `insert(:stage_participation, player_id: nil, team_id: insert(:team).id, category: \"team\")`."
  def stage_participation_factory do
    player = insert(:player)
    stage = build(:stage)

    %StageParticipation{
      player_id: player.id,
      region_id: player.region_id,
      stage_id: stage.id,
      category: player.gender,
      joined_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def group_factory do
    %Group{
      stage_id: build(:stage).id,
      region_id: build(:region).id,
      category: Enum.random(~w(male female team)),
      name: sequence(:group_name, &"Group #{&1}")
    }
  end

  def group_membership_factory do
    %GroupMembership{
      group_id: insert(:group).id,
      stage_participation_id: insert(:stage_participation).id
    }
  end

  @doc """
  Cycles through the 6 Circuit/Finals × male/female/team combos — brackets
  are stage+category unique, and only Circuit/Finals ever get one. Only good
  for 6 inserts before it starts repeating combos (see
  `stage_capacity_config_factory/0`'s identical caveat).
  """
  def knockout_bracket_factory do
    bracket_stages =
      Cuevolution.Repo.all(from s in Stage, where: s.order in [3, 4], order_by: s.order)

    combos = for s <- bracket_stages, category <- ~w(male female team), do: {s, category}
    index = sequence(:knockout_bracket_cycle, & &1)
    {stage, category} = Enum.at(combos, rem(index, length(combos)))

    %KnockoutBracket{stage_id: stage.id, category: category}
  end

  @doc "Round-robin round on a group belonging to the same freshly-picked stage — referentially consistent by default. For a knockout-stage round, override with `group_id: nil, knockout_bracket_id: insert(:knockout_bracket).id`."
  def round_factory do
    stage = build(:stage)

    %Round{
      stage_id: stage.id,
      group_id: insert(:group, stage_id: stage.id).id,
      name: sequence(:round_name, &"Round #{&1}")
    }
  end

  @doc "Builds two same-category/same-stage participations, a round on that stage, and a venue — a fully referentially-consistent Fixture."
  def fixture_factory do
    stage = build(:stage)
    category = Enum.random(["male", "female"])
    participant_a = insert(:stage_participation, stage_id: stage.id, category: category)
    participant_b = insert(:stage_participation, stage_id: stage.id, category: category)
    round = insert(:round, stage_id: stage.id)

    %Fixture{
      round_id: round.id,
      participant_a_id: participant_a.id,
      participant_b_id: participant_b.id,
      venue_id: insert(:venue).id,
      scheduled_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  @doc "A recorded result for a freshly-built fixture, winner defaults to participant A."
  def match_result_factory do
    fixture = insert(:fixture)

    %MatchResult{
      fixture_id: fixture.id,
      winner_participation_id: fixture.participant_a_id,
      recorded_by_admin_id: insert(:admin).id
    }
  end

  @doc "One frame of a Team-category match result — home/away players default to two freshly-built players, winner defaults to home."
  def match_frame_factory do
    home = insert(:player)
    away = insert(:player)

    %MatchFrame{
      match_result_id: insert(:match_result).id,
      home_player_id: home.id,
      away_player_id: away.id,
      winner_player_id: home.id,
      sequence: sequence(:frame_sequence, & &1) + 1
    }
  end

  @doc "A Cuevo Points entry against a freshly-built match result, awarded to that result's winner by default."
  def cuevo_points_entry_factory do
    result = insert(:match_result)

    %CuevoPointsEntry{
      participant_id: result.winner_participation_id,
      match_result_id: result.id,
      points: 3,
      recorded_by_admin_id: insert(:admin).id
    }
  end
end
