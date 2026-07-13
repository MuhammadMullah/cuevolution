defmodule Cuevolution.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
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

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
