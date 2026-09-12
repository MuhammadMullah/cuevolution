defmodule CuevolutionWeb.AdminManagementLive do
  @moduledoc """
  Super-admin-only "Admins" page: invite a Tournament Manager, Regional
  Coordinator, or Venue Representative by email. The invited admin gets an
  email to set their password and mobile number before they can sign in
  (`AdminSetupLive`) — role-specific permissions are out of scope for now.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias CuevolutionWeb.AdminComponents

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Admins",
       role_options: Enum.map(Admin.invitable_roles(), &{Admin.role_label(&1), &1})
     )
     |> assign_form(Admin.invite_changeset(%Admin{}, %{}))
     |> load_admins()}
  end

  def handle_event("validate", %{"admin" => params}, socket) do
    changeset =
      %Admin{}
      |> Admin.invite_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("invite", %{"admin" => params}, socket) do
    setup_url_fun = fn token -> url(~p"/admin/setup/#{token}") end

    case Accounts.invite_admin(socket.assigns.current_admin, params, setup_url_fun) do
      {:ok, admin} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Invitation sent to #{admin.email} as #{Admin.role_label(admin.role)}."
         )
         |> assign_form(Admin.invite_changeset(%Admin{}, %{}))
         |> load_admins()}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp load_admins(socket) do
    assign(socket, :admins, Accounts.list_admins())
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :admin))
  end

  @doc false
  def status_label(admin), do: if(Admin.pending?(admin), do: "Invited", else: "Active")

  @doc false
  def status_badge_class(admin) do
    if Admin.pending?(admin), do: "bg-ink-100 text-ink-700", else: "bg-[#DCF3E4] text-[#0E6A30]"
  end
end
