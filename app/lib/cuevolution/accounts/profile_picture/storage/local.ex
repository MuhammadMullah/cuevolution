defmodule Cuevolution.Accounts.ProfilePicture.Storage.Local do
  @moduledoc "Dev/test default — writes under this app's own priv/static/uploads, served by Plug.Static. Never used in production (see Storage.Backblaze)."
  @behaviour Cuevolution.Accounts.ProfilePicture.Storage

  @impl true
  def put(key, body, _content_type) do
    dest = Path.join([:code.priv_dir(:cuevolution), "static", "uploads", key])
    File.mkdir_p!(Path.dirname(dest))
    File.write!(dest, body)
    {:ok, "/uploads/#{key}"}
  end
end
