defmodule Cuevolution.Seeds.Admins do
  @moduledoc """
  Seeds one active account for every admin role.

  Idempotent — safe to run on its own or through `priv/repo/seeds.exs`.
  Existing accounts are left unchanged so re-running seeds never resets a
  password or lifecycle state.
  """

  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Repo

  @admins [
    {"admin@cuevolutionke.com", "Admin@Cue26", "super_admin"},
    {"director@cuevolutionke.com", "Director@Cue26", "tournament_director"},
    {"coordinator@cuevolutionke.com", "Coordinator@C26", "regional_coordinator"},
    {"venue.rep@cuevolutionke.com", "VenueRep@Cue26", "venue_representative"}
  ]

  def run do
    Enum.each(@admins, &seed_admin/1)
  end

  defp seed_admin({email, password, role}) do
    case Repo.get_by(Admin, email: email) do
      nil ->
        {:ok, _admin} =
          %Admin{}
          |> Admin.registration_changeset(%{email: email, password: password, role: role})
          |> Repo.insert()

        IO.puts("Seeded #{Admin.role_label(role)}: #{email} / #{password}")

      _admin ->
        IO.puts("Admin already seeded: #{email}")
    end
  end
end

Cuevolution.Seeds.Admins.run()
