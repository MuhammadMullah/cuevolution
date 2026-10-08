defmodule Cuevolution.Seeds.VenueRepresentatives do
  @moduledoc """
  Imports venue representatives as admin accounts, batch by batch.

  `run/0` imports the original 40-contact master list the normal way: a
  pending account invited by email (`Accounts.invite_admin/3`). Existing
  admin emails are skipped. Existing venues are reused where the master
  list uses a shortened name; otherwise a new active venue is created in
  the representative's region before the invitation is queued.

      mix run -e 'Cuevolution.Seeds.VenueRepresentatives.run()'

  `run_central_region_direct/0` is a different shape for a later, smaller
  batch (the 22 Central-region reps) — created directly with a shared
  temporary password instead of an email invite, since email delivery has
  been unreliable. See its own doc for the override/skip rules.

      mix run -e 'Cuevolution.Seeds.VenueRepresentatives.run_central_region_direct()'
  """

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Accounts.Region
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias Cuevolution.Venues.Venue
  alias CuevolutionWeb.Endpoint

  @region_aliases %{
    "Coast Region" => "Coast",
    "Nyanza / Western" => "Nyanza & Western"
  }

  @venue_aliases %{
    "kapande" => "Kapande Pool Club (Wilson)",
    "walletsloungeutawala" => "Wallets (Utawala)",
    "qbash" => "Qbash Lounge",
    "minglesnyali" => "Mingles (Nyali)",
    "makuli" => "Makuli (Makupa)",
    "screenshot" => "Screenshot (Mtwapa)",
    "savannah" => "Savannah Pool Club",
    "manyattaloungediani" => "Manyatta Lounge (Diani)",
    "rackattack" => "Rack Attack (Kisumu)",
    "space next door" => "Space Next Door",
    "chilistavern" => "Chillis",
    "laikispoolclub" => "Laikis (Narok)",
    "foxys" => "Foxys",
    "lobovillage" => "Lobo Village (Eldoret)",
    "kitale" => "Kitale Sports Club (Kitale)",
    # Central-region contact-list names that already exist under the
    # established "<Name> (<Town>)" convention — confirmed against
    # `venues` directly, not guessed, since the PDF's two tables (contacts
    # vs facilities) use inconsistent name forms for the same venue.
    "aquaticmeru" => "Aquatic (Meru)",
    "thikaroadpoolclub" => "Thika Road Pool Club (Thika)",
    "emiratesplacelimuru" => "Emirates Place (Limuru)",
    "murangasocialhall" => "Muranga Social Hall (Muranga)"
  }

  @contacts [
    %{
      region: "South Rift",
      venue: "Marathon Pool Center",
      name: "Wesley Korir",
      phone: "0790190630",
      email: "wesley504korir@gmail.com"
    },
    %{
      region: "South Rift",
      venue: "Sotik Jaguar Pool Center",
      name: "Evans Tanui",
      phone: "0721717782",
      email: "evansjaguar@gmail.com"
    },
    %{
      region: "South Rift",
      venue: "Rhinoz Bomet",
      name: "Geoffrey Cheruiyot",
      phone: "0723340583",
      email: "kcheruiyotg@gmail.com"
    },
    %{
      region: "South Rift",
      venue: "Nanyorrai Ntulele",
      name: "John Lemeria",
      phone: "0715723610",
      email: "johnkoiyiet02@gmail.com"
    },
    %{
      region: "South Rift",
      venue: "Amalo Classic Pool Center",
      name: "Victor Kibet Korir",
      phone: "0720614333",
      email: "kipskibet76@gmail.com"
    },
    %{
      region: "South Rift",
      venue: "Terek",
      name: "Amos Rono",
      phone: "0706798548",
      email: "kipkiruia4@gmail.com"
    },
    %{
      region: "South Rift",
      venue: "Party Island Naivasha",
      name: "Gerald Nyutu",
      phone: "0705652230",
      email: "geraldnyutu375@gmail.com"
    },
    %{
      region: "South Rift",
      venue: "Space Next Door",
      name: "Rengo Mayak",
      phone: "0743317443",
      email: "rengmayak2000@gmail.com"
    },
    %{
      region: "South Rift",
      venue: "Astuk Siongiroi",
      name: "Kipkirui Cheruiyot",
      phone: "0729933111",
      email: "kcdennoh@gmail.com"
    },
    %{
      region: "South Rift",
      venue: "Chili's Tavern",
      name: "Kenny Elder",
      phone: "0720762087",
      email: "kenkama71@gmail.com"
    },
    %{
      region: "South Rift",
      venue: "Laikis Pool Club",
      name: "Alex Letaya",
      phone: "0721970585",
      email: "nkuletalex@gmail.com"
    },
    %{
      region: "South Rift",
      venue: "Kobel",
      name: "Dalmas Kipkoech Magut",
      phone: "0794203924",
      email: "dalmaskipsmag@gmail.com"
    },
    %{
      region: "South Rift",
      venue: "Lanaca Litein",
      name: "Kevin Ouma",
      phone: "0729127009",
      email: "kevouma1354@gmail.com"
    },
    %{
      region: "Coast Region",
      venue: "Coast Region Rep",
      name: "Mary Muthoni",
      phone: "0708497417",
      email: "marymuthony@gmail.com"
    },
    %{
      region: "Coast Region",
      venue: "Finebreeze Voi",
      name: "Geoffrey Moloimet",
      phone: "0713273887",
      email: "moloimetg@gmail.com"
    },
    %{
      region: "Coast Region",
      venue: "Screenshot",
      name: "Duncan Osoro",
      phone: "0725525900",
      email: "onduncan2@gmail.com"
    },
    %{
      region: "Coast Region",
      venue: "Manyatta Lounge Diani",
      name: "Benson Gwendo",
      phone: "0795443602",
      email: "gwendombuya04@gmail.com"
    },
    %{
      region: "Coast Region",
      venue: "Mingles Nyali",
      name: "Kelvin Kyalo",
      phone: "0793040872",
      email: "kelvinmambo98@gmail.com"
    },
    %{
      region: "Coast Region",
      venue: "Savannah",
      name: "Edwin Githinji",
      phone: "0724137398",
      email: "edumuturi@gmail.com"
    },
    %{
      region: "Coast Region",
      venue: "Bamburi Welfare Club",
      name: "Stephen Mungai",
      phone: "0724539766",
      email: "stevehaji222@gmail.com"
    },
    %{
      region: "Coast Region",
      venue: "RackRoom Makupa",
      name: "Dennis Kiumo",
      phone: "0715735598",
      email: "dennyskiumo@gmail.com"
    },
    %{
      region: "Coast Region",
      venue: "Makuli",
      name: "Irene Kimathi",
      phone: "0715094466",
      email: "kajurene@gmail.com"
    },
    %{
      region: "Coast Region",
      venue: "Kusini Tavern",
      name: "Simon Masha",
      phone: "0723750847",
      email: "schengo@gmail.com"
    },
    %{
      region: "Coast Region",
      venue: "Brizzy Kingstone",
      name: "Sammy Njuguna",
      phone: "0705793768",
      email: "sammynjuguna33@gmail.com"
    },
    %{
      region: "Nairobi A",
      venue: "Kapande",
      name: "Collins",
      phone: "0743906965",
      email: "kogocollins63@gmail.com"
    },
    %{
      region: "Nairobi A",
      venue: "Qbash",
      name: "Samuel Waweru",
      phone: "0742107864",
      email: "wawerusamuel18@gmail.com"
    },
    %{
      region: "Nairobi A",
      venue: "Hash Lounge",
      name: "Joe Njomo",
      phone: "0722590573",
      email: "nyusaeh@gmail.com"
    },
    %{
      region: "Nairobi A",
      venue: "Backyard Sports Lounge",
      name: "Samuel Mbugua",
      phone: "0748949495",
      email: "samshellsmbugua@gmail.com"
    },
    %{
      region: "Nairobi A",
      venue: "Uptown Ngong",
      name: "John Bosire",
      phone: "0740707698",
      email: "jonbi2001@gmail.com"
    },
    %{
      region: "Nairobi A",
      venue: "Framaks Arena",
      name: "Paul Njeri",
      phone: "0748330271",
      email: "phumblehumble@gmail.com"
    },
    %{
      region: "Nairobi A",
      venue: "Wallets Lounge Utawala",
      name: "Victor Ogol",
      phone: "0720844523",
      email: "victorochieng92@gmail.com"
    },
    %{
      region: "Nairobi A",
      venue: "Sikiliza Piranhas",
      name: "Kevin Kimutai",
      phone: "0719771656",
      email: "kimkevo40@gmail.com"
    },
    %{
      region: "Nairobi A",
      venue: "Shooters Pool Club",
      name: "Joseph Ogonda",
      phone: "0702966889",
      email: "josephouma993@gmail.com"
    },
    %{
      region: "Nairobi A",
      venue: "Royal Break Pool Table",
      name: "Calleb",
      phone: "0116211360",
      email: "ontitacalleb@gmail.com"
    },
    %{
      region: "Nyanza / Western",
      venue: "Rack Attack",
      name: "Faraji Juma",
      phone: "0743533167",
      email: "faroukhjumah@gmail.com"
    },
    %{
      region: "North Rift",
      venue: "JCM Marvel Pool Table",
      name: "Danson Kinyua",
      phone: "0711935902",
      email: "kinyuadanson35@gmail.com"
    },
    %{
      region: "North Rift",
      venue: "Riverside 4H Resort Lessos Arena",
      name: nil,
      phone: "0722854295",
      email: "henrybor8@gmail.com"
    },
    %{
      region: "North Rift",
      venue: "FOXY'S",
      name: "Eric Mutuku",
      phone: "0712386168",
      email: "ericngenzi22@gmail.com"
    },
    %{
      region: "North Rift",
      venue: "Lobo Village",
      name: "Jethro Moranga",
      phone: "0723386839",
      email: "m53jethro@gmail.com"
    },
    %{
      region: "North Rift",
      venue: "Kitale",
      name: "Denis Mugah",
      phone: nil,
      email: "mugahdennis2@gmail.com"
    }
  ]

  # Shared by every admin `run_*_direct/0` creates or overrides below — see
  # `run_central_region_direct/0`'s moduledoc for why these bypass the
  # invite-email flow instead of using `@contacts`/`run/0`'s pattern.
  @temporary_password "VenueRep@26"

  @central_region_contacts [
    %{
      venue: "Aquatic Meru",
      name: "Loyford Muthomi",
      phone: "0724329148",
      email: "loyfordsomi@gmail.com"
    },
    %{
      venue: "Billiards Arena Karatina",
      name: "Evanston Mbugua",
      phone: "0757722270",
      email: "evansongachihi@gmail.com"
    },
    %{
      venue: "Black Perch Meru",
      name: "Newton Gatobu",
      phone: "0798269970",
      email: "newtongatobu735@gmail.com"
    },
    %{
      venue: "Capitol Embu",
      name: "Peter Kariuki Mutitu",
      phone: "0728762168",
      email: "peterkariuki2015@gmail.com"
    },
    %{
      venue: "Cue Point Chuka",
      name: "James Maina",
      phone: "0712805083",
      email: "mainajaymo98@gmail.com"
    },
    %{
      venue: "Drafthaus Nanyuki",
      name: "Joseph Mutahi",
      phone: "0719122590",
      email: "josemutahi92@gmail.com"
    },
    %{
      venue: "Emirates Place Limuru",
      name: "Edwin Muhoro",
      phone: "0701760528",
      email: "muhoroedwin59@gmail.com"
    },
    %{
      venue: "Express Lounge & Grill Ol' Kalau",
      name: "Daniel Waweru",
      phone: "0712999184",
      email: "banielwaweru8@gmail.com"
    },
    %{
      venue: "Fieldview Lounge & Grill Kiriaini",
      name: "Sam Mburu",
      phone: "0714893226",
      email: "mburu870@gmail.com"
    },
    %{
      venue: "Gee Spot",
      name: "Harrison Mugambi",
      phone: "0729354463",
      email: "harrisonmugambi05@gmail.com"
    },
    %{
      venue: "Thika Road Pool Club",
      name: "Alphis Wangai",
      phone: "0759142244",
      email: "gichukialphis@gmail.com"
    },
    %{
      venue: "Santiago Pool Club",
      name: "Solomon Kahiga",
      phone: "0719476644",
      email: "sokasuleiman@gmail.com"
    },
    %{
      venue: "Rifles Sports Academy",
      name: "Mark Wanjohi",
      phone: "0713960392",
      email: "markmrt15@gmail.com"
    },
    %{
      venue: "Neighbors Karatina",
      name: "Abijah Mureithi",
      phone: "0703899364",
      email: "kabuiabi7@gmail.com"
    },
    %{
      venue: "Mwembeni Timeless Pools",
      name: "Stephen Kamau",
      phone: "0726804729",
      email: "stephenkamau084@gmail.com"
    },
    %{
      venue: "Mweiga Police Canteen",
      name: "Gabriel Wamutitu",
      phone: "0726552929",
      email: "gabrielwamutitu87@gmail.com"
    },
    %{
      venue: "Muranga Social Hall",
      name: "Charles Macharia",
      phone: "0748074343",
      email: "charles.macharia1638@gmail.com"
    },
    %{
      venue: "Mozambique Billiards",
      name: "Phineas Murithi",
      phone: "0723555686",
      email: "pmurithi09@gmail.com"
    },
    %{
      venue: "Magic Pool Club Nanyuki",
      name: "Emmanuel Torohtich",
      phone: "0795923900",
      email: "torohtichemmanuel@gmail.com"
    },
    %{
      venue: "Kwetu Sports Hub",
      name: "Stephen Mwangi",
      phone: "0720115980",
      email: "stevomwas7040@gmail.com"
    },
    %{
      venue: "Isiolo North Gate",
      name: "Feisal Too",
      phone: "0717143733",
      email: "toofeisal14@gmail.com"
    },
    %{
      venue: "Mathira Bar Karatina",
      name: "James Mwangi Kinyati",
      phone: "0724537548",
      email: "mwangikinyatijames@gmail.com"
    }
  ]

  @doc """
  Creates/overrides the Central-region venue reps directly with a shared
  temporary password instead of an email invite — email delivery has been
  unreliable (see the 2026-10 delivery investigation), so this bypasses it
  entirely. Every account this creates or overrides is flagged
  `must_change_password: true`, which forces a "set a new password" modal
  the first time they log in (see `CuevolutionWeb.AdminAuth.on_mount/4`
  and `CuevolutionWeb.AdminComponents.app_shell/1`).

  Run once, explicitly, from the production console:

      mix run -e 'Cuevolution.Seeds.VenueRepresentatives.run_central_region_direct()'

  Only ever overrides an existing admin if they're still pending
  (`Admin.pending?/1` — never completed their own setup, see
  `Accounts.create_or_reset_pending_admin/1`); an admin who already
  completed setup is left completely untouched, even if their email
  appears in this list.
  """
  def run_central_region_direct do
    central_region_id = Repo.get_by!(Region, name: "Central").id

    report =
      Enum.map(@central_region_contacts, &import_one_direct(&1, central_region_id))

    summary = %{
      created: Enum.count(report, &match?({:created, _}, &1)),
      overridden: Enum.count(report, &match?({:overridden, _}, &1)),
      skipped_active: Enum.count(report, &match?({:skipped_active, _}, &1)),
      failed: Enum.count(report, &match?({:failed, _}, &1)),
      results: report
    }

    IO.puts(
      "Central region direct import complete: #{summary.created} created, " <>
        "#{summary.overridden} overridden (were pending), " <>
        "#{summary.skipped_active} skipped (already active), #{summary.failed} failed. " <>
        "Shared temporary password: #{@temporary_password}"
    )

    summary
  end

  defp import_one_direct(contact, region_id) do
    case find_or_create_venue(contact.venue, region_id) do
      {:ok, venue, _venue_status} ->
        create_or_override_admin(contact, venue)

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, &format_error/1)
        IO.puts("FAILED #{contact.email} (venue): #{inspect(errors)}")
        {:failed, {contact.email, errors}}
    end
  end

  defp create_or_override_admin(contact, venue) do
    attrs = %{
      "email" => String.downcase(contact.email),
      "role" => "venue_representative",
      "venue_id" => venue.id,
      "mobile_number" => contact.phone,
      "password" => @temporary_password
    }

    case Accounts.create_or_reset_pending_admin(attrs) do
      {:ok, :created, admin} ->
        IO.puts("Created #{admin.email} for #{venue.name}")
        {:created, admin.email}

      {:ok, :overridden, admin} ->
        IO.puts("Overrode pending admin #{admin.email} for #{venue.name}")
        {:overridden, admin.email}

      {:error, :already_active} ->
        IO.puts("Skipped #{contact.email} — already active, left untouched")
        {:skipped_active, contact.email}

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, &format_error/1)
        IO.puts("FAILED #{contact.email}: #{inspect(errors)}")
        {:failed, {contact.email, errors}}
    end
  end

  @doc "Imports the venue representatives and queues their setup emails."
  def run do
    inviter = find_inviter!()
    regions = regions_by_name!()

    report =
      Enum.map(@contacts, fn contact ->
        import_one(inviter, contact, Map.fetch!(regions, contact.region))
      end)

    summary = %{
      invited: Enum.count(report, &match?({:invited, _}, &1)),
      skipped: Enum.count(report, &match?({:skipped, _}, &1)),
      failed: Enum.count(report, &match?({:failed, _}, &1)),
      venues_created: Enum.count(report, &match?({:invited, %{venue_status: :created}}, &1)),
      results: report
    }

    print_summary(summary)
    summary
  end

  defp import_one(inviter, contact, region_id) do
    case Repo.get_by(Admin, email: contact.email) do
      %Admin{} = existing ->
        IO.puts("Skipped existing admin #{contact.email} (#{Admin.role_label(existing.role)})")
        {:skipped, contact.email}

      nil ->
        with {:ok, venue, venue_status} <- find_or_create_venue(contact.venue, region_id),
             {:ok, admin} <-
               Accounts.invite_admin(inviter, invite_attrs(contact, venue.id), &setup_url/1) do
          IO.puts("Invited #{contact.email} for #{venue.name}")
          {:invited, %{email: admin.email, venue_status: venue_status}}
        else
          {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
            errors = Ecto.Changeset.traverse_errors(changeset, &format_error/1)
            IO.puts("FAILED #{contact.email}: #{inspect(errors)}")
            {:failed, {contact.email, errors}}

          {:error, reason} ->
            IO.puts("FAILED #{contact.email}: #{inspect(reason)}")
            {:failed, {contact.email, reason}}
        end
    end
  end

  defp find_or_create_venue(name, region_id) do
    canonical_name = Map.get(@venue_aliases, normalize(name), name)

    case Repo.one(active_venue_query(canonical_name, region_id)) do
      %Venue{} = venue ->
        {:ok, venue, :existing}

      nil ->
        case Venues.create_venue(%{name: canonical_name, region_id: region_id}) do
          {:ok, venue} -> {:ok, venue, :created}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp active_venue_query(name, region_id) do
    from venue in Venue,
      where: venue.region_id == ^region_id and venue.active,
      where: fragment("lower(trim(?))", venue.name) == ^String.downcase(name)
  end

  defp invite_attrs(contact, venue_id) do
    %{
      "email" => contact.email,
      "role" => "venue_representative",
      "venue_id" => venue_id,
      "mobile_number" => contact.phone
    }
  end

  defp find_inviter! do
    query =
      from admin in Admin,
        where:
          admin.role == "super_admin" and is_nil(admin.suspended_at) and
            is_nil(admin.removed_at),
        order_by: [asc: admin.inserted_at],
        limit: 1

    case Repo.one(query) do
      %Admin{} = admin -> admin
      nil -> raise "Could not find an active super admin; run the admin seeds first."
    end
  end

  defp regions_by_name! do
    regions = Repo.all(Region) |> Map.new(&{&1.name, &1.id})

    missing =
      @contacts
      |> Enum.map(&Map.get(@region_aliases, &1.region, &1.region))
      |> Enum.uniq()
      |> then(&(&1 -- Map.keys(regions)))

    if missing != [] do
      raise "Missing region seed(s): #{Enum.join(missing, ", ")}. Run the region seeds first."
    end

    Map.new(@contacts, fn contact ->
      {contact.region,
       Map.fetch!(regions, Map.get(@region_aliases, contact.region, contact.region))}
    end)
  end

  defp setup_url(token), do: Endpoint.url() <> "/admin/setup/#{token}"

  defp normalize(name), do: name |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")

  defp format_error({message, metadata}) do
    Enum.reduce(metadata, message, fn {key, value}, error ->
      String.replace(error, "%{#{key}}", to_string(value))
    end)
  end

  defp print_summary(%{
         invited: invited,
         skipped: skipped,
         failed: failed,
         venues_created: venues_created
       }) do
    IO.puts(
      "Venue representative import complete: #{invited} invited, #{skipped} skipped, " <>
        "#{failed} failed, #{venues_created} venues created."
    )
  end
end
