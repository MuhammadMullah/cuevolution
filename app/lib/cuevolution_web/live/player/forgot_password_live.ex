defmodule CuevolutionWeb.ForgotPasswordLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias CuevolutionWeb.PlayerComponents

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Forgot Password",
       stage: :request,
       login: nil,
       error: nil,
       form: to_form(%{}, as: :forgot)
     )}
  end

  def handle_event("send_reset", %{"forgot" => %{"login" => login}}, socket) do
    trimmed = String.trim(login)

    if trimmed == "" do
      {:noreply,
       socket
       |> assign(:form, to_form(%{"login" => login}, as: :forgot))
       |> assign(:error, "Enter your email or username to continue.")}
    else
      deliver_reset(trimmed)
      {:noreply, assign(socket, stage: :sent, login: trimmed, error: nil)}
    end
  end

  def handle_event("resend", _params, socket) do
    deliver_reset(socket.assigns.login)
    {:noreply, socket}
  end

  # Always no-ops silently when `login` matches no player — the caller
  # (both the initial submit and resend) shows the same "check your email"
  # state either way, so account existence is never revealed (spec 011
  # FR-002).
  defp deliver_reset(login) do
    if player = Accounts.get_player_by_login(login) do
      Accounts.deliver_player_reset_password_instructions(
        player,
        &url(~p"/reset-password/#{&1}")
      )
    end
  end
end
