defmodule CuevolutionWeb.PostmarkWebhookController do
  @moduledoc """
  Receives Postmark's Bounce and SpamComplaint webhooks.

  `Mailer.deliver/1` returning `{:ok, _}` only means Postmark *accepted*
  the send for delivery — actual bounces and spam complaints happen later,
  asynchronously, and are reported here, not at send time. Without this
  endpoint, a "successfully sent" email that then bounces is invisible to
  the app entirely. Every event is logged regardless of whether it
  correlates to a tracked row, so even email types with no status column
  (e.g. password resets) leave a searchable trail.

  Configure this URL (with Basic Auth credentials — see `authenticate/2`)
  under Bounce and SpamComplaint on the Postmark server's webhook settings.
  """
  use CuevolutionWeb, :controller

  require Logger

  alias Cuevolution.Accounts
  alias Cuevolution.Notifications

  plug :authenticate

  def create(conn, %{"RecordType" => record_type, "Email" => email} = params)
      when record_type in ["Bounce", "SpamComplaint"] do
    Logger.error(
      "postmark webhook record_type=#{record_type} email=#{email} " <>
        "type=#{params["Type"]} message_id=#{params["MessageID"]} " <>
        "description=#{params["Description"]}"
    )

    Notifications.mark_bounced(email)
    Accounts.mark_invite_email_bounced(email)

    send_resp(conn, 200, "")
  end

  def create(conn, _params), do: send_resp(conn, 200, "")

  defp authenticate(conn, _opts) do
    case Application.get_env(:cuevolution, :postmark_webhook) do
      [username: username, password: password]
      when is_binary(username) and is_binary(password) ->
        Plug.BasicAuth.basic_auth(conn, username: username, password: password)

      _ ->
        conn |> send_resp(503, "") |> halt()
    end
  end
end
