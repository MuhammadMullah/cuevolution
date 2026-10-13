defmodule CuevolutionWeb.ForgotPasswordLive do
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.RateLimiter
  alias CuevolutionWeb.PlayerComponents

  # Per login, per window. Counts attempts for unknown logins too, so being
  # limited never reveals whether an account exists.
  @max_requests 5
  @window_ms :timer.minutes(15)

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
      case deliver_reset(trimmed) do
        :ok ->
          {:noreply, assign(socket, stage: :sent, login: trimmed, error: nil)}

        {:error, :rate_limited, retry_after_ms} ->
          {:noreply,
           socket
           |> assign(:form, to_form(%{"login" => login}, as: :forgot))
           |> assign(:error, rate_limited_message(retry_after_ms))}
      end
    end
  end

  def handle_event("resend", _params, socket) do
    case deliver_reset(socket.assigns.login) do
      :ok ->
        {:noreply, socket}

      {:error, :rate_limited, retry_after_ms} ->
        {:noreply, put_flash(socket, :error, rate_limited_message(retry_after_ms))}
    end
  end

  # Always no-ops silently when `login` matches no player — the caller
  # (both the initial submit and resend) shows the same "check your email"
  # state either way, so account existence is never revealed (spec 011
  # FR-002).
  defp deliver_reset(login) do
    with :ok <-
           RateLimiter.hit({:player_reset, String.downcase(login)}, @max_requests, @window_ms) do
      if player = Accounts.get_player_by_login(login) do
        Accounts.deliver_player_reset_password_instructions(
          player,
          &url(~p"/reset-password/#{&1}")
        )
      end

      :ok
    end
  end

  defp rate_limited_message(retry_after_ms) do
    minutes = max(ceil(retry_after_ms / 60_000), 1)

    "Too many reset requests. Please try again in #{minutes} #{if minutes == 1, do: "minute", else: "minutes"}."
  end
end
