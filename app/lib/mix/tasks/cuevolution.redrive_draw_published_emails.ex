defmodule Mix.Tasks.Cuevolution.RedriveDrawPublishedEmails do
  @moduledoc """
  Re-queues up to `limit` failed/stuck "draw_published" email
  notifications for another delivery attempt (2026-09 incident: Gmail
  SMTP's sending cap exhausted by a large draw-publish batch). Defaults
  to 400, comfortably under a personal Gmail account's ~500/day cap — run
  it again for the next batch once you're confident there's send quota
  available, rather than draining the whole backlog in one shot.

  Usage: mix cuevolution.redrive_draw_published_emails [limit]

  In a production release (no Mix), use
  `Cuevolution.Release.redrive_draw_published_emails/1` instead — both
  call `Cuevolution.Notifications.redrive_failed/3`.
  """
  @shortdoc "Re-queues failed/stuck draw_published email notifications"

  use Mix.Task

  alias Cuevolution.Notifications

  def run(args) do
    Mix.Task.run("app.start")

    limit =
      case args do
        [limit_str] -> String.to_integer(limit_str)
        [] -> 400
      end

    {requeued, remaining} = Notifications.redrive_failed("draw_published", "email", limit)

    Mix.shell().info("Re-queued #{requeued} email notification(s) for another attempt.")
    Mix.shell().info("#{remaining} still failed/stuck.")
  end
end
