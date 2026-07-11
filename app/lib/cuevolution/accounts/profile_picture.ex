defmodule Cuevolution.Accounts.ProfilePicture do
  @moduledoc """
  Resizes and stores a player's uploaded profile picture (design-system.md
  §10): the original upload is never stored — only a re-encoded derivative
  capped at a fixed maximum dimension.
  """

  @max_dimension 512

  @doc """
  Resizes the image at `source_path` (never upscaled, only shrunk if
  larger) and saves it as a JPEG under `priv/static/uploads/players/`,
  named `filename_base.jpg`. Returns the public path to store on the
  player record.
  """
  def store(source_path, filename_base) do
    dest_dir = upload_dir()
    File.mkdir_p!(dest_dir)
    dest_path = Path.join(dest_dir, "#{filename_base}.jpg")

    source_path
    |> Mogrify.open()
    |> Mogrify.format("jpg")
    |> Mogrify.resize("#{@max_dimension}x#{@max_dimension}>")
    |> Mogrify.save(path: dest_path)

    {:ok, "/uploads/players/#{filename_base}.jpg"}
  rescue
    error -> {:error, error}
  end

  # Defaults to the app's own priv/static (fine for dev/test, and matches
  # where Plug.Static serves /uploads from). In production this is
  # overridden (see config/runtime.exs) to a path outside the release —
  # priv/static lives inside the release's versioned directory, which is
  # replaced wholesale on every deploy, so anything written there doesn't
  # survive a redeploy. The overridden path is on a volume Caddy serves
  # directly, bypassing the app for reads.
  defp upload_dir do
    base =
      Application.get_env(
        :cuevolution,
        :uploads_dir,
        Path.join([:code.priv_dir(:cuevolution), "static", "uploads"])
      )

    Path.join(base, "players")
  end
end
