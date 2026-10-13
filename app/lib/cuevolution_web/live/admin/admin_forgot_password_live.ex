defmodule CuevolutionWeb.AdminForgotPasswordLive do
  @moduledoc """
  Lets an admin request a password-reset link by email. Always shows the
  same "check your email" confirmation whether or not the email matches an
  eligible admin, so account existence is never revealed.
  """
  use CuevolutionWeb, :live_view

  alias Cuevolution.Accounts
  alias Cuevolution.RateLimiter
  alias CuevolutionWeb.AdminComponents

  # Per email, per window. Counts attempts for unknown emails too, so being
  # limited never reveals whether an account exists.
  @max_requests 5
  @window_ms :timer.minutes(30)

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Forgot Password",
       stage: :request,
       email: nil,
       error: nil,
       form: to_form(%{}, as: :forgot)
     )}
  end

  def handle_event("send_reset", %{"forgot" => %{"email" => email}}, socket) do
    trimmed = String.trim(email)

    if trimmed == "" do
      {:noreply,
       socket
       |> assign(:form, to_form(%{"email" => email}, as: :forgot))
       |> assign(:error, "Enter your email to continue.")}
    else
      case deliver_reset(trimmed) do
        :ok ->
          {:noreply, assign(socket, stage: :sent, email: trimmed, error: nil)}

        {:error, :rate_limited, retry_after_ms} ->
          {:noreply,
           socket
           |> assign(:form, to_form(%{"email" => email}, as: :forgot))
           |> assign(:error, rate_limited_message(retry_after_ms))}
      end
    end
  end

  def handle_event("resend", _params, socket) do
    case deliver_reset(socket.assigns.email) do
      :ok ->
        {:noreply, socket}

      {:error, :rate_limited, retry_after_ms} ->
        {:noreply, put_flash(socket, :error, rate_limited_message(retry_after_ms))}
    end
  end

  defp deliver_reset(email) do
    with :ok <- RateLimiter.hit({:admin_reset, String.downcase(email)}, @max_requests, @window_ms) do
      if admin = Accounts.get_admin_by_email(email) do
        Accounts.deliver_admin_reset_password_instructions(
          admin,
          &url(~p"/admin/reset-password/#{&1}")
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
