defmodule Cuevolution.Accounts.ProfilePicture do
  @moduledoc """
  Resizes and stores a player's uploaded profile picture (design-system.md
  §10): the original upload is never stored — only a re-encoded derivative
  capped at a fixed maximum dimension. Where the result ends up (local
  disk in dev/test, Backblaze B2 in production) is decided by the
  configured `Storage` backend — see `Cuevolution.Accounts.ProfilePicture.Storage`.
  """

  alias Cuevolution.Accounts.ProfilePicture.Storage

  @max_dimension 512

  @doc """
  Resizes the image at `source_path` (never upscaled, only shrunk if
  larger), re-encodes it as JPEG, and hands the bytes to the configured
  storage backend under `players/filename_base.jpg`. Returns the public
  URL to store on the player record.
  """
  def store(source_path, filename_base) do
    tmp_path = Path.join(System.tmp_dir!(), "#{filename_base}.jpg")

    source_path
    |> Mogrify.open()
    |> Mogrify.format("jpg")
    |> Mogrify.resize("#{@max_dimension}x#{@max_dimension}>")
    |> Mogrify.save(path: tmp_path)

    result = storage().put("players/#{filename_base}.jpg", File.read!(tmp_path), "image/jpeg")
    File.rm(tmp_path)
    result
  rescue
    error -> {:error, error}
  end

  defp storage, do: Application.get_env(:cuevolution, :profile_picture_storage, Storage.Local)
end
