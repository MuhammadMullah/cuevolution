defmodule Cuevolution.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  alias Cuevolution.Seeds.VenueRepresentatives

  @app :cuevolution

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Runs a seed file from priv/repo/seeds/ in a release (no Mix, so
  `mix run FILE` isn't available). Starts the full app, not just the
  repo — accounts_seeds.exs in particular calls Accounts.register_player/1,
  which dispatches a notification through Oban, so the repo alone (as
  migrate/0 starts) isn't enough. Each seed file is self-executing (calls
  its own `Module.run()` at the bottom), so requiring it is enough. E.g.:

      bin/cuevolution eval 'Cuevolution.Release.seed("regions_seeds.exs")'
  """
  def seed(filename) do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    :cuevolution
    |> Application.app_dir(Path.join("priv/repo/seeds", filename))
    |> Code.require_file()

    :ok
  end

  @doc """
  Enrolls every player/team that predates auto-enrollment into Grassroots
  (spec 006). Idempotent — safe to re-run. E.g.:

      bin/cuevolution eval 'Cuevolution.Release.backfill_grassroots()'
  """
  def backfill_grassroots do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    %{players: {player_count, player_errors}, teams: {team_count, team_errors}} =
      Cuevolution.Competitions.backfill_grassroots_enrollments()

    IO.puts("Enrolled #{player_count} player(s) and #{team_count} team(s) into Grassroots.")

    for {id, changeset} <- player_errors ++ team_errors do
      IO.puts(:stderr, "Failed to enroll #{id}: #{inspect(changeset.errors)}")
    end

    :ok
  end

  @doc """
  One-time: moves every existing female player's and team's current
  Grassroots `StageParticipation` to Regional, now that ladies and teams
  start there directly. Idempotent — safe to re-run. E.g.:

      bin/cuevolution eval 'Cuevolution.Release.migrate_regional_start()'
  """
  def migrate_regional_start do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    %{moved: moved, skipped_drawn: skipped_drawn} =
      Cuevolution.Competitions.migrate_regional_start_enrollments()

    IO.puts(
      "Moved #{moved} participant(s) to Regional (skipped #{skipped_drawn} already drawn into a Grassroots group)."
    )

    :ok
  end

  @doc """
  One-off: grants `:tournament_eligibility_override` to every player who
  registered between 21 and 25 September 2026 (UTC-naive, matching the
  existing `Accounts.tournament_registration_cutoff/0` EAT-midnight
  convention) — the tournament committee's decision to admit these late
  registrants into this season's draw. Idempotent — safe to re-run. E.g.:

      bin/cuevolution eval 'Cuevolution.Release.grant_late_registrant_override()'
  """
  def grant_late_registrant_override do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    {:ok, usernames} =
      Cuevolution.Accounts.grant_tournament_eligibility_override(
        ~N[2026-09-20 21:00:00],
        ~N[2026-09-25 21:00:00]
      )

    IO.puts("Granted tournament_eligibility_override to #{length(usernames)} player(s):")
    Enum.each(usernames, &IO.puts("  @#{&1}"))

    :ok
  end

  @doc """
  Re-queues up to `limit` failed/stuck "draw_published" email
  notifications for another delivery attempt after a provider rejection or
  outage (see `Cuevolution.Notifications.redrive_failed/3`). Defaults to 400;
  run it again for the next batch once you're confident there is send
  capacity available, rather than draining the whole backlog in one shot and
  re-triggering the same throttling. E.g.:

      bin/cuevolution eval 'Cuevolution.Release.redrive_draw_published_emails()'
      bin/cuevolution eval 'Cuevolution.Release.redrive_draw_published_emails(100)'
  """
  def redrive_draw_published_emails(limit \\ 400) do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    {requeued, remaining} =
      Cuevolution.Notifications.redrive_failed("draw_published", "email", limit)

    IO.puts("Re-queued #{requeued} email notification(s) for another attempt.")

    IO.puts(
      "#{remaining} still failed/stuck — run again once you're sure there's send quota left."
    )

    :ok
  end

  @doc """
  One-off: creates/overrides the Central-region venue reps directly with a
  shared temporary password instead of an email invite — see
  `Cuevolution.Seeds.VenueRepresentatives.run_central_region_direct/0` for
  the override/skip rules (only ever overrides an admin still pending;
  never touches one who's already active). Safe to re-run — already-active
  accounts from a prior run are just skipped. E.g.:

      bin/cuevolution eval 'Cuevolution.Release.seed_central_region_venue_reps()'
  """
  def seed_central_region_venue_reps do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    VenueRepresentatives.run_central_region_direct()

    :ok
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
