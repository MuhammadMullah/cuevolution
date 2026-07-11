defmodule Cuevolution.Notifications do
  @moduledoc """
  Placeholder for the Notifications context (spec 002 — Context 2 of
  `project-scope/tasks.md`, not yet built).

  Only `dispatch/3`'s signature exists here so `Accounts.register_player/1`
  (T025) has a real boundary to call against. The full dispatch pipeline —
  payload allowlisting, idempotent sends, Oban email/SMS workers, retries —
  lands with Context 2 (T036-T048) and replaces this module's body.
  """

  require Logger

  @doc "Placeholder dispatch — logs the notification intent. Replaced by Context 2's real implementation."
  def dispatch(_recipient, event_type, _payload) do
    Logger.info(
      "notification dispatch requested (Notifications context not yet built): #{event_type}"
    )

    :ok
  end
end
