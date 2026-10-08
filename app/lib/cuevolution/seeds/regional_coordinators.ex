defmodule Cuevolution.Seeds.RegionalCoordinators do
  @moduledoc """
  Imports regional coordinators as admin accounts, batch by batch.

  `run/0` imports the original 8-region master list the normal way: a
  pending account invited by email (`Accounts.invite_admin/3`), same as an
  admin invited from the admin-management screen. Idempotent by email —
  existing admin records are reported and left unchanged.

      mix run -e 'Cuevolution.Seeds.RegionalCoordinators.run()'

  `run_direct/0` is a different shape for later, one-off additions —
  created directly with a shared temporary password instead of an email
  invite, since email delivery has been unreliable (see
  `Cuevolution.Seeds.VenueRepresentatives.run_central_region_direct/0`,
  same rationale). See its own doc for the override/skip rules.

      mix run -e 'Cuevolution.Seeds.RegionalCoordinators.run_direct()'
  """

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Accounts.Region
  alias Cuevolution.Repo
  alias CuevolutionWeb.Endpoint

  @regional_representatives [
    %{
      name: "Clinton Kosgei",
      region: "Nairobi A",
      mobile_number: "0795 847969",
      email: "clinton.koskei@gmail.com"
    },
    %{
      name: "Cyrus Maina",
      region: "Nairobi B",
      mobile_number: "0726 734850",
      email: "mainagcyrus@gmail.com"
    },
    %{
      name: "Mark Wanjohi",
      region: "Central",
      mobile_number: "0713 960392",
      email: "markmrt15@gmail.com"
    },
    %{
      name: "Mary Nganga",
      region: "Coast",
      mobile_number: "0708 497417",
      email: "marymuthony@gmail.com"
    },
    %{
      name: "Pasio Nganda",
      region: "Eastern",
      mobile_number: "0721 260780",
      email: "pasiodan44@gmail.com"
    },
    %{
      name: "Vinny Kiprotich",
      region: "North Rift",
      mobile_number: "0727 827814",
      email: "vlimokipro@gmail.com"
    },
    %{
      name: "Liaram Molai",
      region: "South Rift",
      mobile_number: "0720 996529",
      email: "mliaram1983@gmail.com"
    },
    %{
      name: "Nafeez Kara",
      region: "Nyanza & Western",
      mobile_number: "0722 339966",
      email: "Nafeezkara11@gmail.com"
    }
  ]

  @temporary_password "RegionCoord@26"

  @direct_regional_coordinators [
    %{
      name: "Kiprono Ismael",
      region: "South Rift",
      mobile_number: "+254797773049",
      email: "Kipronoismael0@gmail.com"
    }
  ]

  @doc """
  Creates/overrides regional coordinators directly with a shared temporary
  password instead of an email invite — see
  `Cuevolution.Seeds.VenueRepresentatives.run_central_region_direct/0` for
  the full rationale and the override/skip rules (only ever overrides an
  admin still pending; never touches one who's already active).

  Run once, explicitly, from the production console:

      bin/cuevolution eval 'Cuevolution.Release.seed_regional_coordinators_direct()'

  or locally with:

      mix run -e 'Cuevolution.Seeds.RegionalCoordinators.run_direct()'
  """
  def run_direct do
    regions = regions_by_name!()

    report = Enum.map(@direct_regional_coordinators, &import_one_direct(&1, regions))

    summary = %{
      created: Enum.count(report, &match?({:created, _}, &1)),
      overridden: Enum.count(report, &match?({:overridden, _}, &1)),
      skipped_active: Enum.count(report, &match?({:skipped_active, _}, &1)),
      failed: Enum.count(report, &match?({:failed, _}, &1)),
      results: report
    }

    IO.puts(
      "Regional coordinator direct import complete: #{summary.created} created, " <>
        "#{summary.overridden} overridden (were pending), " <>
        "#{summary.skipped_active} skipped (already active), #{summary.failed} failed. " <>
        "Shared temporary password: #{@temporary_password}"
    )

    summary
  end

  defp import_one_direct(contact, regions) do
    attrs = %{
      "email" => String.downcase(contact.email),
      "role" => "regional_coordinator",
      "region_id" => Map.fetch!(regions, contact.region),
      "mobile_number" => contact.mobile_number,
      "password" => @temporary_password
    }

    case Accounts.create_or_reset_pending_admin(attrs) do
      {:ok, :created, admin} ->
        IO.puts("Created #{admin.email} for #{contact.region}")
        {:created, admin.email}

      {:ok, :overridden, admin} ->
        IO.puts("Overrode pending admin #{admin.email} for #{contact.region}")
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

  @doc "Imports the eight regional coordinators and queues their setup emails."
  def run do
    inviter = find_inviter!()
    regions = regions_by_name!()

    report =
      Enum.map(@regional_representatives, fn representative ->
        attrs =
          representative
          |> Map.put(:role, "regional_coordinator")
          |> Map.put(:region_id, Map.fetch!(regions, representative.region))
          |> stringify_keys()

        import_one(inviter, representative, attrs)
      end)

    summary = %{
      invited: Enum.count(report, &match?({:invited, _}, &1)),
      skipped: Enum.count(report, &match?({:skipped, _}, &1)),
      failed: Enum.count(report, &match?({:failed, _}, &1)),
      results: report
    }

    print_summary(summary)
    summary
  end

  defp import_one(inviter, representative, attrs) do
    case Repo.get_by(Admin, email: representative.email) do
      nil ->
        case Accounts.invite_admin(inviter, attrs, &setup_url/1) do
          {:ok, admin} ->
            IO.puts("Invited #{representative.name} (#{representative.region}) <#{admin.email}>")
            {:invited, admin.email}

          {:error, changeset} ->
            errors = Ecto.Changeset.traverse_errors(changeset, &format_error/1)
            IO.puts("FAILED #{representative.email}: #{inspect(errors)}")
            {:failed, {representative.email, errors}}
        end

      existing ->
        IO.puts(
          "Skipped existing admin #{representative.email} (#{Admin.role_label(existing.role)})"
        )

        {:skipped, representative.email}
    end
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
    representative_regions = Enum.map(@regional_representatives, & &1.region)
    missing = Enum.uniq(representative_regions -- Map.keys(regions))

    if missing != [] do
      raise "Missing region seed(s): #{Enum.join(missing, ", ")}. Run the region seeds first."
    end

    regions
  end

  defp setup_url(token), do: Endpoint.url() <> "/admin/setup/#{token}"

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)

  defp format_error({message, metadata}) do
    Enum.reduce(metadata, message, fn {key, value}, error ->
      String.replace(error, "%{#{key}}", to_string(value))
    end)
  end

  defp print_summary(%{invited: invited, skipped: skipped, failed: failed}) do
    IO.puts(
      "Regional coordinator import complete: #{invited} invited, #{skipped} skipped, #{failed} failed."
    )
  end
end
