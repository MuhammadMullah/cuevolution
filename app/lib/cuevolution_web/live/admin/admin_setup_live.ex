defmodule CuevolutionWeb.AdminSetupLive do
  @moduledoc """
  Lets a newly invited admin (see `AdminManagementLive`) set their password
  and mobile number before they can sign in. Reached only via the one-time
  link emailed by `Cuevolution.Notifications.Emails.admin_invitation/2`.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias CuevolutionWeb.AdminComponents

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_admin_by_setup_token(token) do
      %Admin{} = admin ->
        {:ok,
         assign(socket,
           page_title: "Set Up Your Account",
           stage: :form,
           admin: admin,
           form: to_form(Admin.setup_changeset(admin, %{}), as: :admin)
         )}

      nil ->
        {:ok, assign(socket, page_title: "Set Up Your Account", stage: :invalid)}
    end
  end

  def handle_event("validate", %{"admin" => params}, socket) do
    changeset =
      socket.assigns.admin
      |> Admin.setup_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :admin))}
  end

  def handle_event("complete_setup", %{"admin" => params}, socket) do
    case Accounts.complete_admin_setup(socket.assigns.admin, params) do
      {:ok, _admin} ->
        {:noreply, assign(socket, stage: :done)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :admin))}
    end
  end
end
