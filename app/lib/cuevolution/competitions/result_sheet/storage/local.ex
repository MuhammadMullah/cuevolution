defmodule Cuevolution.Competitions.ResultSheet.Storage.Local do
  @moduledoc "Dev/test default — writes under this app's own priv/static/uploads, served by Plug.Static. Never used in production (see Storage.GCS)."
  @behaviour Cuevolution.Competitions.ResultSheet.Storage

  @impl true
  def put(key, body, _content_type) do
    dest = Path.join([:code.priv_dir(:cuevolution), "static", "uploads", key])
    File.mkdir_p!(Path.dirname(dest))
    File.write!(dest, body)
    :ok
  end

  @impl true
  def url(key), do: "/uploads/#{key}"
end
