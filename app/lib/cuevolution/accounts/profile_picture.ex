defmodule Cuevolution.Accounts.ProfilePicture do
  @moduledoc """
  Resizes and stores a player's uploaded profile picture (design-system.md
  §10): the original upload is never stored — only a re-encoded derivative
  capped at a fixed maximum dimension. Where the result ends up (local
  disk in dev/test, AWS S3 in production) is decided by the configured
  `Storage` backend — see `Cuevolution.Accounts.ProfilePicture.Storage`.
  """

  alias Cuevolution.Accounts.ProfilePicture.Storage

  @max_dimension 512

  @doc """
  Resizes the image at `source_path` (never upscaled, only shrunk if
  larger), re-encodes it as JPEG, and hands the bytes to the configured
  storage backend under `players/filename_base.jpg`. Returns the storage
  **key** to persist on the player record — never a URL. In production
  the bucket is private, so a displayable URL is a short-lived presigned
  one generated fresh by `url/1`, not something that can be stored once
  and reused.
  """
  def store(source_path, filename_base) do
    tmp_path = Path.join(System.tmp_dir!(), "#{filename_base}.jpg")

    source_path
    |> Mogrify.open()
    |> Mogrify.format("jpg")
    |> Mogrify.resize("#{@max_dimension}x#{@max_dimension}>")
    |> Mogrify.save(path: tmp_path)

    key = "players/#{filename_base}.jpg"

    result =
      case storage().put(key, File.read!(tmp_path), "image/jpeg") do
        :ok -> {:ok, key}
        {:error, reason} -> {:error, reason}
      end

    File.rm(tmp_path)
    result
  rescue
    error -> {:error, error}
  end

  @doc "Turns a stored key (from `store/2`) back into something a browser can load. `nil` in, `nil` out — players without a photo."
  def url(nil), do: nil
  def url(key), do: storage().url(key)

  defp storage, do: Application.get_env(:cuevolution, :profile_picture_storage, Storage.Local)
end
