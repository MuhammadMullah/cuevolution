defmodule CuevolutionWeb.AdminManagementLive do
  @moduledoc """
  User-management page for Super Admins and Tournament Directors. The latter
  may manage every role except Super Admins.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Venues
  alias CuevolutionWeb.AdminComponents

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Admins",
       role_options: Enum.map(Admin.invitable_roles(), &{Admin.role_label(&1), &1}),
       venue_options: venue_options()
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

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to invite admins.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("change_role", %{"target_id" => id, "role" => %{"role" => role}}, socket) do
    with %Admin{} = target <- find_admin(socket, id),
         {:ok, _target} <- Accounts.update_admin_role(socket.assigns.current_admin, target, role) do
      {:noreply,
       socket
       |> put_flash(:info, "#{target.email} is now #{Admin.role_label(role)}.")
       |> load_admins()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "That admin no longer exists.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can't change that admin's role.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't update that role.")}
    end
  end

  def handle_event(
        "change_venue",
        %{"target_id" => id, "venue" => %{"venue_id" => venue_id}},
        socket
      ) do
    with %Admin{} = target <- find_admin(socket, id),
         {:ok, _target} <-
           Accounts.update_admin_venue(socket.assigns.current_admin, target, venue_id) do
      {:noreply, socket |> put_flash(:info, "Venue assignment updated.") |> load_admins()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "That admin no longer exists.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can't change that venue assignment.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't update that venue assignment.")}
    end
  end

  def handle_event("toggle_suspend", %{"id" => id}, socket) do
    with %Admin{} = target <- find_admin(socket, id),
         result <-
           if(Admin.suspended?(target),
             do: Accounts.reinstate_admin(socket.assigns.current_admin, target),
             else: Accounts.suspend_admin(socket.assigns.current_admin, target)
           ),
         {:ok, _target} <- result do
      action = if Admin.suspended?(target), do: "reinstated", else: "suspended"
      {:noreply, socket |> put_flash(:info, "#{target.email} #{action}.") |> load_admins()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "That admin no longer exists.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can't suspend that admin.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't update that admin.")}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    with %Admin{} = target <- find_admin(socket, id),
         {:ok, _target} <- Accounts.remove_admin(socket.assigns.current_admin, target) do
      {:noreply,
       socket |> put_flash(:info, "#{target.email} removed from the admin team.") |> load_admins()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "That admin no longer exists.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can't remove that admin.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't remove that admin.")}
    end
  end

  defp load_admins(socket) do
    assign(socket, :admins, Accounts.list_admins())
  end

  defp venue_options do
    Venues.list_venues(%{active: true}) |> Enum.map(&{&1.name, &1.id})
  end

  defp find_admin(socket, id), do: Enum.find(socket.assigns.admins, &(&1.id == id))

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :admin))
  end

  @doc false
  def status_badge_class(admin) do
    cond do
      Admin.pending?(admin) -> "bg-[#FEF3E2] text-[#92400E]"
      Admin.suspended?(admin) -> "bg-[#FDECEA] text-[#A81810]"
      true -> "bg-[#DCF3E4] text-[#0E6A30]"
    end
  end

  def status_label(%Admin{} = admin) do
    cond do
      Admin.pending?(admin) -> "Invited"
      Admin.suspended?(admin) -> "Suspended"
      true -> "Active"
    end
  end

  def role_options_for(%Admin{} = actor, %Admin{} = target) do
    Admin.roles()
    |> Enum.filter(&(actor.role == "super_admin" or &1 != "super_admin" or &1 == target.role))
    |> Enum.map(&{Admin.role_label(&1), &1})
  end
end
