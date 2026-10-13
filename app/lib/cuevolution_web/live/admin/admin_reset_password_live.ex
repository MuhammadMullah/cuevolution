defmodule CuevolutionWeb.AdminResetPasswordLive do
  @moduledoc """
  Lets an admin choose a new password via the one-time link emailed by
  `Cuevolution.Notifications.Emails.admin_reset_password_instructions/2`.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias CuevolutionWeb.AdminComponents

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_admin_by_reset_password_token(token) do
      %Admin{} = admin ->
        {:ok,
         assign(socket,
           page_title: "Reset Password",
           stage: :form,
           admin: admin,
           form: to_form(Admin.reset_password_changeset(admin, %{}), as: :admin)
         )}

      nil ->
        {:ok, assign(socket, page_title: "Reset Password", stage: :invalid)}
    end
  end

  def handle_event("validate", %{"admin" => params}, socket) do
    changeset =
      socket.assigns.admin
      |> Admin.reset_password_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :admin))}
  end

  def handle_event("reset_password", %{"admin" => params}, socket) do
    case Accounts.reset_admin_password(socket.assigns.admin, params) do
      {:ok, _admin} ->
        {:noreply, assign(socket, stage: :done)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :admin))}
    end
  end
end
