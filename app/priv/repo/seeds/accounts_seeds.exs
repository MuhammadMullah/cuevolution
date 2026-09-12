defmodule Cuevolution.Seeds.Accounts do
  @moduledoc """
  Seeds the default admin account and a batch of sample players.
  Idempotent — safe to re-run. Depends on `Cuevolution.Seeds.Venues` having
  already run (players need a venue to select at registration).

  Players are bulk-inserted via `Repo.insert_all/3` in `@batch_size` chunks
  rather than one at a time through `Accounts.register_player/1` — hashing
  a password per row and dispatching a notification per row is what made
  seeding thousands of players take minutes; batching keeps it to seconds.
  """

  import Ecto.Query

  alias Cuevolution.Accounts.{Admin, Player, Region}
  alias Cuevolution.Competitions
  alias Cuevolution.Competitions.StageParticipation
  alias Cuevolution.Repo
  alias Cuevolution.Venues.Venue

  @admin_email "admin@cuevolutionke.com"
  @admin_password "Admin@Cue26"
  @player_count 5000
  @player_username_prefix "seedplayer"
  @player_password "Valid1!Pass"
  @batch_size 1000

  # Common Kenyan given names, split by gender, drawn from across the
  # country's major communities (Kikuyu, Luo, Luhya, Kalenjin, Kamba, Meru,
  # Kisii, Coastal/Swahili, Somali) so the seeded roster reads as national,
  # matching the venues it's spread across.
  @male_first_names ~w(
    James John Peter David Daniel Samuel Joseph Paul Stephen Michael Kevin
    Brian Dennis Felix Victor Erick Collins Bernard Charles Anthony Patrick
    Francis Vincent Martin Simon Duncan Edwin Elvis Fredrick Geoffrey Hillary
    Ian Job Kelvin Lawrence Moses Nicholas Oscar Philip Robert Timothy Walter
    Wilson Zachary Otieno Odhiambo Omondi Owino Onyango Wafula Wanyama Barasa
    Simiyu Kiptoo Kiplagat Kipchoge Kiprotich Cheruiyot Mutua Kioko Musyoka
    Kariuki Njoroge Maina Gitau Karanja Mburu Hassan Mohamed Abdi Ali Omar
    Yusuf Ibrahim
  )

  @female_first_names ~w(
    Mary Grace Faith Joyce Jane Catherine Elizabeth Esther Eunice Lucy
    Margaret Alice Beatrice Christine Diana Edith Florence Gladys Hellen
    Irene Janet Judith Millicent Naomi Pauline Rose Susan Teresa Veronica
    Winnie Agnes Brenda Cynthia Doreen Emily Fiona Gloria Ivy Jacinta Kelly
    Linda Mercy Nancy Olivia Phoebe Ruth Sharon Tabitha Vivian Wambui
    Wanjiku Wangari Nyambura Njeri Muthoni Akinyi Adhiambo Atieno Awuor
    Nafula Nekesa Naliaka Jepkosgei Jelagat Jepchirchir Chebet Chepkoech
    Amina Fatuma Halima
  )

  @surnames ~w(
    Mwangi Kamau Njoroge Kariuki Maina Kimani Otieno Odhiambo Omondi Owino
    Onyango Ochieng Ouma Odongo Okello Wafula Wanyonyi Barasa Simiyu Wekesa
    Nabwire Kiptoo Kiplagat Kipchoge Kiprotich Cheruiyot Bett Kimutai
    Chepkemoi Mutua Kioko Musyoka Mwendwa Kilonzo Muthama Nzomo Mutuku
    Miriti Mwiti Kaberia Bosire Nyakundi Mogaka Onchoke Nyaga Gichuki
    Wachira Muriuki Karanja Gitau Mburu Ndungu Njuguna Macharia Kinyua
    Njiru Waweru Thuo Hassan Mohamed Abdi Ali Omar Yusuf Ibrahim Noor Farah
    Abdullahi Mwakio Kazungu Charo Baraka Kahindi Nzai Karisa Ngala Mwaguni
    Mwakisha
  )

  def run do
    seed_admin()
    seed_players()
  end

  defp seed_admin do
    case Repo.get_by(Admin, email: @admin_email) do
      nil ->
        {:ok, _admin} =
          %Admin{}
          |> Admin.registration_changeset(%{
            email: @admin_email,
            password: @admin_password,
            role: "super_admin"
          })
          |> Repo.insert()

        IO.puts("Seeded admin: #{@admin_email} / #{@admin_password}")

      _admin ->
        IO.puts("Admin already seeded: #{@admin_email}")
    end
  end

  defp seed_players do
    already_seeded =
      Repo.aggregate(
        from(p in Player, where: like(p.username, ^"#{@player_username_prefix}%")),
        :count
      )

    if already_seeded >= @player_count do
      IO.puts("Players already seeded (#{already_seeded}).")
    else
      # Ordering by id (a random UUID) rather than by region interleaves
      # regions from the very first cycle, so round-robining over this list
      # spreads players evenly across every venue in the country instead of
      # exhausting one region before moving to the next.
      venues = Repo.all(from v in Venue, where: v.active == true, order_by: v.id)
      regions_by_id = Repo.all(Region) |> Map.new(&{&1.id, &1})
      grassroots_stage_id = Competitions.grassroots_stage().id

      # Hashed once and reused for every seed player (bulk `insert_all`
      # bypasses `Player.registration_changeset/2` entirely, so nothing else
      # would hash it) — hashing per-row via the real changeset is what made
      # seeding 5000 players take minutes instead of seconds.
      hashed_password = Bcrypt.hash_pwd_salt(@player_password)

      (already_seeded + 1)..@player_count
      |> Enum.chunk_every(@batch_size)
      |> Enum.each(&seed_batch(&1, venues, regions_by_id, grassroots_stage_id, hashed_password))

      IO.puts("Seeded players #{already_seeded + 1}..#{@player_count}.")
    end
  end

  # Bulk-inserts a batch of players and their Grassroots `StageParticipation`
  # rows via `insert_all`, skipping changesets/callbacks (and so the
  # registration-confirmation notification `Accounts.register_player/1`
  # would otherwise dispatch — not wanted for bulk-seeded fixture data).
  defp seed_batch(ns, venues, regions_by_id, grassroots_stage_id, hashed_password) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    joined_at = DateTime.utc_now() |> DateTime.truncate(:second)

    {players, participations} =
      ns
      |> Enum.map(
        &build_player(
          &1,
          venues,
          regions_by_id,
          grassroots_stage_id,
          hashed_password,
          now,
          joined_at
        )
      )
      |> Enum.unzip()

    Repo.transaction(fn ->
      Repo.insert_all(Player, players)
      Repo.insert_all(StageParticipation, participations)
    end)
  end

  defp build_player(
         n,
         venues,
         regions_by_id,
         grassroots_stage_id,
         hashed_password,
         now,
         joined_at
       ) do
    venue = Enum.at(venues, rem(n - 1, length(venues)))
    region = Map.fetch!(regions_by_id, venue.region_id)
    gender = if rem(n, 2) == 0, do: "male", else: "female"
    first_names = if gender == "male", do: @male_first_names, else: @female_first_names

    first_name = Enum.at(first_names, :erlang.phash2({n, :first}, length(first_names)))
    last_name = Enum.at(@surnames, :erlang.phash2({n, :last}, length(@surnames)))
    age = 18 + :erlang.phash2({n, :age}, 33)
    day_offset = :erlang.phash2({n, :day}, 365)
    date_of_birth = Date.utc_today() |> Date.add(-(age * 365 + day_offset))
    player_id = Ecto.UUID.generate()

    player = %{
      id: player_id,
      first_name: first_name,
      last_name: last_name,
      date_of_birth: date_of_birth,
      gender: gender,
      email: "#{@player_username_prefix}#{n}@cuevolution.test",
      mobile_number: "+2547#{String.pad_leading(Integer.to_string(n), 8, "0")}",
      location: region.name,
      country: "KE",
      username: "#{@player_username_prefix}#{n}",
      notification_preference: "email",
      hashed_password: hashed_password,
      region_id: region.id,
      preferred_venue_id: venue.id,
      inserted_at: now,
      updated_at: now
    }

    participation = %{
      id: Ecto.UUID.generate(),
      player_id: player_id,
      region_id: region.id,
      stage_id: grassroots_stage_id,
      category: gender,
      joined_at: joined_at,
      inserted_at: now,
      updated_at: now
    }

    {player, participation}
  end
end

Cuevolution.Seeds.Accounts.run()
