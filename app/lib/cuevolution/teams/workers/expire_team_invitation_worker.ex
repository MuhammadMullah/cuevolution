defmodule Cuevolution.Teams.Workers.ExpireTeamInvitationWorker do
  @moduledoc """
  Flips a `TeamInvitation` from "pending" to "expired" 48 hours after it was
  sent (scheduled by `Cuevolution.Teams.invite_player/2` via `schedule_in:`).

  Purely a bookkeeping sweep for listings (banner, captain dashboard) — the
  authoritative check is the live `expires_at` comparison in
  `Teams.accept_invitation/2`/`decline_invitation/2`, so a delayed or missed
  run here can never let an expired invitation be accepted.

  Idempotent: a plain conditional `update_all` scoped to `status: "pending"`,
  same style as `Teams.lock_roster/1` — a no-op if the invitation was
  already accepted/declined/cancelled by the time this runs.
  """
  use Oban.Worker, queue: :notifications, max_attempts: 5

  import Ecto.Query

  alias Cuevolution.Repo
  alias Cuevolution.Teams.TeamInvitation

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"invitation_id" => invitation_id}}) do
    TeamInvitation
    |> where([i], i.id == ^invitation_id and i.status == "pending")
    |> Repo.update_all(set: [status: "expired"])

    :ok
  end
end
