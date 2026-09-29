defmodule Cuevolution.Seeds.RegionalCoordinators do
  @moduledoc """
  Imports the regional representatives supplied for the 2026 Sportpesa National
  Pool Circuit as pending regional-coordinator admin accounts.

  Run explicitly with:

      mix run -e 'Cuevolution.Seeds.RegionalCoordinators.run()'

  The operation is idempotent by email. Existing admin records are reported and
  left unchanged; new records receive the same setup email as an admin invited
  from the admin-management screen.
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
