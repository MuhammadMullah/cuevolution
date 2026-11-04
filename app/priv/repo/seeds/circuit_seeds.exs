defmodule Cuevolution.Seeds.Circuit do
  @moduledoc """
  Seeds a Circuit field so the draw, the live bracket and SP Points can be
  exercised end to end locally.

  Creates its own players rather than moving existing ones: a seeded player's
  pipeline state (Grassroots, Regional) is what the other seeds set up, and
  repointing them would quietly break those flows. These carry the
  `circuitdemo` username prefix so they are easy to spot and easy to remove.

  Idempotent — re-running tops the field back up to the requested size rather
  than adding a second batch.

      mix run priv/repo/seeds/circuit_seeds.exs                      # 128 men, 64 ladies
      CIRCUIT_MEN=32 CIRCUIT_LADIES=16 mix run priv/repo/seeds/circuit_seeds.exs

  To watch SP Points fill in without clicking through every match, play the
  bracket out from IEx (`iex -S mix`):

      Cuevolution.Seeds.Circuit.simulate("male")
      Cuevolution.Competitions.sp_points_standings(bracket_id)
  """

  import Ecto.Query

  alias Cuevolution.Accounts.Player
  alias Cuevolution.Accounts.Region
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.Fixture
  alias Cuevolution.Competitions.Round
  alias Cuevolution.Competitions.StageParticipation
  alias Cuevolution.Repo
  alias Cuevolution.Teams.Team
  alias Cuevolution.Venues.Venue

  @prefix "circuitdemo"
  @password "Valid1!Pass"
  @team_prefix "Demo"

  @first_names_male ~w(
    James Peter David Samuel Joseph Stephen Kevin Brian Dennis Felix Victor
    Erick Collins Anthony Patrick Vincent Martin Duncan Edwin Moses Nicholas
    Oscar Philip Robert Timothy Wilson Otieno Omondi Wafula Simiyu Kiptoo
    Cheruiyot Mutua Kariuki Njoroge Maina Gitau Mburu Hassan Mohamed Ali Omar
    Yusuf Ibrahim Zachary Walter Lawrence Geoffrey Hillary Elvis
  )

  @first_names_female ~w(
    Mary Grace Faith Joyce Jane Catherine Elizabeth Esther Eunice Lucy
    Margaret Alice Beatrice Christine Diana Edith Florence Gladys Hellen
    Irene Janet Judith Naomi Pauline Rose Susan Teresa Veronica Winnie Agnes
    Brenda Cynthia Doreen Emily Fiona Gloria Ivy Jacinta Kelly Mercy Linet
    Sharon Lilian Cynthia Nelly Purity Damaris Zippora Everlyne Caroline
  )

  @surnames ~w(
    Otieno Odhiambo Omondi Owino Onyango Wafula Wanyama Barasa Simiyu Kiptoo
    Kiplagat Cheruiyot Mutua Kioko Musyoka Kariuki Njoroge Maina Gitau Karanja
    Mburu Hassan Mohamed Abdi Ali Omar Yusuf Ibrahim Wekesa Nyaga Korir Langat
    Macharia Mwenga Chebet Kamau Mbugua Rotich Shikuku Githinji
  )

  def run do
    # The real field sizes from the format sheet. Override for a smaller
    # field when you want to click through a whole bracket quickly.
    men = env("CIRCUIT_MEN", 128)
    ladies = env("CIRCUIT_LADIES", 64)
    teams = env("CIRCUIT_TEAMS", 20)

    stage = Competitions.circuit_stage()

    seed_category(stage, "male", men)
    seed_category(stage, "female", ladies)
    seed_teams(stage, teams)

    IO.puts("""

    Circuit field ready.
      men:    #{Competitions.circuit_entrant_count(stage.id, "male")}
      ladies: #{Competitions.circuit_entrant_count(stage.id, "female")}
      teams:  #{Competitions.circuit_entrant_count(stage.id, "team")}

    Sign in at /admin/login as director@cuevolutionke.com (Director@Cue26),
    open /admin/groups, pick the Circuit stage tab and press "Make the draw".
    """)
  end

  defp env(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  defp seed_category(stage, category, target) do
    existing = Competitions.circuit_entrant_count(stage.id, category)
    missing = max(target - existing, 0)

    if missing > 0 do
      region_ids = Repo.all(from r in Region, select: r.id)
      venue_ids = Repo.all(from v in Venue, select: v.id)
      taken = Repo.one(from p in Player, where: like(p.username, ^"#{@prefix}%"), select: count())

      for n <- (taken + 1)..(taken + missing) do
        create_entrant(stage, category, n, region_ids, venue_ids)
      end
    end
  end

  defp create_entrant(stage, category, n, region_ids, venue_ids) do
    first =
      if category == "male",
        do: Enum.random(@first_names_male),
        else: Enum.random(@first_names_female)

    region_id = Enum.random(region_ids)

    {:ok, player} =
      %Player{}
      |> Player.registration_changeset(%{
        first_name: first,
        last_name: Enum.random(@surnames),
        # Comfortably over 18 so the age validation passes.
        date_of_birth: Date.add(Date.utc_today(), -365 * Enum.random(20..40)),
        gender: category,
        email: "#{@prefix}#{n}@cuevolution.test",
        mobile_number: "+2547#{String.pad_leading(to_string(90_000_000 + n), 8, "0")}",
        location: "Nairobi",
        username: "#{@prefix}#{n}",
        identification_type: "national_id",
        identification_number: "CD#{n}",
        notification_preference: "email",
        password: @password,
        password_confirmation: @password,
        region_id: region_id,
        preferred_venue_id: Enum.random(venue_ids)
      })
      |> Repo.insert()

    Repo.insert!(%StageParticipation{
      player_id: player.id,
      region_id: region_id,
      stage_id: stage.id,
      category: category,
      joined_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  @team_prefixes ~w(
    Eldoret Nakuru Mombasa Kisumu Nairobi Thika Nyeri Machakos Kakamega Meru
    Embu Kericho Naivasha Malindi Kitale Garissa Narok Voi Bungoma Kisii
  )

  @team_suffixes ~w(Cues Kings Aces Breakers Potters Sharks Legends Stars Royals Rockets)

  # A team entrant is a `stage_participation` with a team_id and no player_id,
  # which is the other half of the `exactly_one_participant_type` constraint.
  # Each team needs a captain, so one is drawn from the demo players.
  defp seed_teams(stage, target) do
    existing = Competitions.circuit_entrant_count(stage.id, "team")
    missing = max(target - existing, 0)

    if missing > 0 do
      captains =
        Repo.all(
          from p in Player,
            where: like(p.username, ^"#{@prefix}%"),
            limit: ^(missing * 2),
            select: p
        )

      taken = Repo.one(from t in Team, where: like(t.name, ^"#{@team_prefix}%"), select: count())

      for n <- (taken + 1)..(taken + missing) do
        create_team(stage, n, Enum.at(captains, rem(n, max(length(captains), 1))))
      end
    end
  end

  defp create_team(_stage, _n, nil), do: :ok

  defp create_team(stage, n, captain) do
    name =
      "#{@team_prefix} #{Enum.at(@team_prefixes, rem(n, length(@team_prefixes)))} " <>
        Enum.at(@team_suffixes, rem(n, length(@team_suffixes)))

    team =
      Repo.insert!(%Team{
        name: name,
        region_id: captain.region_id,
        captain_id: captain.id
      })

    Repo.insert!(%StageParticipation{
      team_id: team.id,
      region_id: captain.region_id,
      stage_id: stage.id,
      category: "team",
      joined_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  @doc """
  Plays the bracket out round by round, giving every match to whoever is in
  slot A, so the whole chart and the SP Points table fill in without clicking
  through each match by hand. Local testing only.

  Pass `rounds:` to stop part way and leave the rest in play, which is what
  you want to see the live scoring and "waiting for players" states together.
  """
  def simulate(category, opts \\ []) do
    stage = Competitions.circuit_stage()
    bracket = Competitions.get_knockout_bracket(stage.id, category)
    admin = Repo.get_by!(Cuevolution.Accounts.Admin, email: "director@cuevolutionke.com")

    if is_nil(bracket) do
      IO.puts("No #{category} bracket drawn yet — make the draw first.")
    else
      round_ids =
        Repo.all(
          from r in Round,
            where: r.knockout_bracket_id == ^bracket.id,
            order_by: [asc: r.sequence],
            select: r.id
        )

      round_ids
      |> Enum.take(Keyword.get(opts, :rounds, length(round_ids)))
      |> Enum.each(&play_round(&1, admin))

      IO.puts("Played #{category} bracket. Standings:")

      bracket.id
      |> Competitions.sp_points_standings()
      |> Enum.take(10)
      |> Enum.each(fn row ->
        IO.puts(
          "  #{String.pad_trailing(row.participation.player.username, 16)} " <>
            "#{row.wins} wins  #{row.points} pts  #{row.finish}"
        )
      end)
    end
  end

  defp play_round(round_id, admin) do
    Repo.all(
      from f in Fixture,
        where: f.round_id == ^round_id and is_nil(f.result_id) and f.bye == false,
        order_by: [asc: f.slot]
    )
    |> Enum.each(fn fixture ->
      if fixture.participant_a_id && fixture.participant_b_id do
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => fixture.participant_a_id,
          "score" => %{"a" => 6, "b" => Enum.random(0..5)}
        })
      end
    end)
  end

  @doc """
  Draws the Circuit team event if it is not drawn yet, then plays `rounds:` of
  the round robin and prints both group tables.

  Winners are picked at random rather than always slot A, so the tables come
  out uneven and the top-four cut is actually worth looking at. Nine rounds is
  the whole season, so `rounds: 3` is one circuit leg's worth.

      mix run -e 'Code.require_file("priv/repo/seeds/circuit_seeds.exs"); Cuevolution.Seeds.Circuit.simulate_teams(rounds: 3)'
  """
  def simulate_teams(opts \\ []) do
    stage = Competitions.circuit_stage()
    admin = Repo.get_by!(Cuevolution.Accounts.Admin, email: "director@cuevolutionke.com")

    ensure_team_draw(stage, admin)

    case Competitions.circuit_team_draw(stage.id) do
      nil ->
        IO.puts("No team draw — are there at least 10 teams entered?")

      _draw ->
        rounds = Competitions.circuit_team_rounds(stage.id)
        last = rounds |> Enum.map(& &1.sequence) |> Enum.max(fn -> 0 end)
        play_to = Keyword.get(opts, :rounds, last)

        rounds
        |> Enum.filter(&(&1.sequence <= play_to))
        |> Enum.each(&play_team_round(&1, admin))

        IO.puts("Played team rounds 1-#{play_to} of #{last}.")
        print_team_tables(stage.id)
    end
  end

  defp ensure_team_draw(stage, admin) do
    if is_nil(Competitions.circuit_team_draw(stage.id)) do
      case Competitions.draw_circuit_team_groups(stage.id, admin) do
        {:ok, %{groups: groups}} ->
          IO.puts("Drew the team event into #{length(groups)} groups.")

        {:error, reason} ->
          IO.puts("Could not draw the team event: #{inspect(reason)}")
      end
    end
  end

  defp play_team_round(round, admin) do
    Enum.each(round.fixtures, fn fixture ->
      if is_nil(fixture.result_id) && fixture.participant_a_id && fixture.participant_b_id do
        record_team_match(fixture, admin, round.race_to || 14)
      end
    end)
  end

  defp record_team_match(fixture, admin, race_to) do
    loser_frames = Enum.random(0..(race_to - 1))

    {winner_id, score} =
      if Enum.random([true, false]) do
        {fixture.participant_a_id, %{"a" => race_to, "b" => loser_frames}}
      else
        {fixture.participant_b_id, %{"a" => loser_frames, "b" => race_to}}
      end

    Competitions.record_result(fixture, admin, %{
      "winner_participation_id" => winner_id,
      "score" => score
    })
  end

  defp print_team_tables(stage_id) do
    Enum.each(Competitions.circuit_team_standings(stage_id), fn %{group: group, rows: rows} ->
      IO.puts("\n#{group.name}")

      Enum.each(rows, fn row ->
        IO.puts(
          "  #{String.pad_leading(to_string(row.rank), 2)}. " <>
            "#{String.pad_trailing(row.name, 24)} " <>
            "#{row.wins}W #{row.losses}L  " <>
            "FD #{String.pad_leading(to_string(row.frame_diff), 4)}  " <>
            "#{String.pad_leading(to_string(row.sp_points), 3)} pts" <>
            if(row.advancing, do: "  -> Nationals", else: "")
        )
      end)
    end)
  end
end

Cuevolution.Seeds.Circuit.run()
