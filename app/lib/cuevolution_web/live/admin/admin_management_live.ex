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
  alias Phoenix.LiveView.JS

  @page_size 10

  @status_options [
    {"Active", "active"},
    {"Invited", "invited"},
    {"Invite revoked", "revoked"},
    {"Suspended", "suspended"}
  ]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Admins",
       role_options: Enum.map(Admin.invitable_roles(), &{Admin.role_label(&1), &1}),
       venue_options: venue_options(),
       region_options: region_options(),
       editing_id: nil,
       editing_role: nil,
       show_invite_modal: false,
       invite_role: nil,
       invite_venue_region_filter: nil,
       status_options: @status_options,
       filter_role_options: Enum.map(Admin.roles(), &{Admin.role_label(&1), &1}),
       status_filter: nil,
       role_filter: nil,
       page: 1
     )
     |> assign_form(Admin.invite_changeset(%Admin{}, %{}))
     |> assign_filter_form()
     |> load_admins()}
  end

  def handle_event("validate", %{"admin" => params} = full_params, socket) do
    changeset =
      %Admin{}
      |> Admin.invite_changeset(params)
      |> Map.put(:action, :validate)

    venue_region_filter = blank_to_nil(full_params["venue_region_filter"])

    {:noreply,
     socket
     |> assign(:invite_role, params["role"])
     |> assign(:invite_venue_region_filter, venue_region_filter)
     |> assign(:venue_options, venue_options(venue_region_filter))
     |> assign_form(changeset)}
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
         |> assign(:venue_options, venue_options())
         |> assign(:show_invite_modal, false)
         |> assign(:invite_role, nil)
         |> assign(:invite_venue_region_filter, nil)
         |> assign_form(Admin.invite_changeset(%Admin{}, %{}))
         |> assign(:page, 1)
         |> load_admins()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to invite admins.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("show_invite_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_invite_modal, true)
     |> assign(:invite_role, nil)
     |> assign(:invite_venue_region_filter, nil)
     |> assign(:venue_options, venue_options())
     |> assign_form(Admin.invite_changeset(%Admin{}, %{}))}
  end

  def handle_event("hide_invite_modal", _params, socket) do
    {:noreply, assign(socket, :show_invite_modal, false)}
  end

  def handle_event("filter", %{"filter" => params}, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, blank_to_nil(params["status"]))
     |> assign(:role_filter, blank_to_nil(params["role"]))
     |> assign(:page, 1)
     |> assign_filter_form()
     |> load_admins()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, nil)
     |> assign(:role_filter, nil)
     |> assign(:page, 1)
     |> assign_filter_form()
     |> load_admins()}
  end

  def handle_event("page", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:page, page_number(page))
     |> load_admins()}
  end

  def handle_event("edit_admin", %{"id" => id}, socket) do
    case {socket.assigns.editing_id, find_admin(socket, id)} do
      {^id, _} ->
        {:noreply, assign(socket, editing_id: nil, editing_role: nil)}

      {_, %Admin{} = target} ->
        if Admin.manageable_by?(socket.assigns.current_admin, target) do
          {:noreply, assign(socket, editing_id: id, editing_role: target.role)}
        else
          {:noreply, socket}
        end

      {_, nil} ->
        {:noreply, put_flash(socket, :error, "That admin no longer exists.")}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil, editing_role: nil)}
  end

  def handle_event("preview_edit_role", %{"admin" => %{"role" => role}}, socket) do
    {:noreply, assign(socket, :editing_role, role)}
  end

  def handle_event("save_edit", %{"target_id" => id, "admin" => params}, socket) do
    actor = socket.assigns.current_admin

    with %Admin{} = target <- find_admin(socket, id),
         {:ok, target} <- maybe_update_role(actor, target, params["role"]),
         {:ok, target} <-
           maybe_update_scope(actor, target, params["venue_id"], params["region_id"]),
         {:ok, _target} <- maybe_update_mobile(actor, target, params["mobile_number"]) do
      {:noreply,
       socket
       |> put_flash(:info, "#{target.email} updated.")
       |> assign(editing_id: nil, editing_role: nil)
       |> load_admins()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "That admin no longer exists.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to make that change.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't save those changes.")}
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

  def handle_event("revoke_invite", %{"id" => id}, socket) do
    with %Admin{} = target <- find_admin(socket, id),
         {:ok, _target} <- Accounts.revoke_invite(socket.assigns.current_admin, target) do
      {:noreply,
       socket |> put_flash(:info, "Invite for #{target.email} revoked.") |> load_admins()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "That admin no longer exists.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can't revoke that invite.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't revoke that invite.")}
    end
  end

  def handle_event("resend_invite", %{"id" => id}, socket) do
    setup_url_fun = fn token -> url(~p"/admin/setup/#{token}") end

    with %Admin{} = target <- find_admin(socket, id),
         {:ok, _target} <-
           Accounts.resend_invite(socket.assigns.current_admin, target, setup_url_fun) do
      {:noreply, socket |> put_flash(:info, "Invite resent to #{target.email}.") |> load_admins()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "That admin no longer exists.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can't resend that invite.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't resend that invite.")}
    end
  end

  defp load_admins(socket) do
    %{status_filter: status, role_filter: role, page: page} = socket.assigns
    filter_opts = %{status: status, role: role}
    total_count = Accounts.count_admins(filter_opts)
    total_pages = max(1, ceil(total_count / @page_size))
    page = min(page, total_pages)

    admins =
      Accounts.list_admins(
        Map.merge(filter_opts, %{limit: @page_size, offset: (page - 1) * @page_size})
      )

    assign(socket, admins: admins, total_count: total_count, total_pages: total_pages, page: page)
  end

  defp assign_filter_form(socket) do
    params = %{"status" => socket.assigns.status_filter, "role" => socket.assigns.role_filter}
    assign(socket, :filter_form, to_form(params, as: :filter))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp page_number(page) when is_integer(page) and page > 0, do: page

  defp page_number(page) when is_binary(page) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp page_number(_page), do: 1

  defp venue_options do
    Venues.list_venues(%{active: true}) |> Enum.map(&{&1.name, &1.id})
  end

  defp venue_options(region_id) when is_binary(region_id) and region_id != "" do
    Venues.list_active_for_region(region_id) |> Enum.map(&{&1.name, &1.id})
  end

  defp venue_options(_region_id), do: venue_options()

  defp region_options do
    Accounts.list_regions() |> Enum.map(&{&1.name, &1.id})
  end

  defp maybe_update_role(_actor, target, role) when role in [nil, ""], do: {:ok, target}
  defp maybe_update_role(_actor, %{role: role} = target, role), do: {:ok, target}
  defp maybe_update_role(actor, target, role), do: Accounts.update_admin_role(actor, target, role)

  defp maybe_update_scope(actor, %{role: "venue_representative"} = target, venue_id, _region_id),
    do: Accounts.update_admin_venue(actor, target, venue_id)

  defp maybe_update_scope(actor, %{role: "regional_coordinator"} = target, _venue_id, region_id),
    do: Accounts.update_admin_region(actor, target, region_id)

  defp maybe_update_scope(_actor, target, _venue_id, _region_id), do: {:ok, target}

  defp maybe_update_mobile(_actor, target, mobile_number)
       when mobile_number in [nil, ""] or mobile_number == target.mobile_number,
       do: {:ok, target}

  defp maybe_update_mobile(actor, target, mobile_number),
    do: Accounts.update_admin_mobile(actor, target, mobile_number)

  defp find_admin(socket, id), do: Enum.find(socket.assigns.admins, &(&1.id == id))

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :admin))
  end

  @doc false
  def status_badge_class(admin) do
    cond do
      Admin.invite_revoked?(admin) -> "bg-ink-200 text-ink-600"
      Admin.pending?(admin) -> "bg-[#FEF3E2] text-[#92400E]"
      Admin.suspended?(admin) -> "bg-[#FDECEA] text-[#A81810]"
      true -> "bg-[#DCF3E4] text-[#0E6A30]"
    end
  end

  def status_label(%Admin{} = admin) do
    cond do
      Admin.invite_revoked?(admin) -> "Invite revoked"
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
