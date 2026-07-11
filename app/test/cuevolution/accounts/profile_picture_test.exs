defmodule Cuevolution.Accounts.ProfilePictureTest do
  use ExUnit.Case, async: false

  alias Cuevolution.Accounts.ProfilePicture

  @moduletag :tmp_dir

  setup do
    on_exit(fn -> Application.delete_env(:cuevolution, :uploads_dir) end)
  end

  test "stores under the default priv/static/uploads/players dir when :uploads_dir isn't configured" do
    fixture = Path.join(:code.priv_dir(:cuevolution), "static/favicon.ico")
    assert {:ok, public_path} = ProfilePicture.store(fixture, "default-dir-test")
    assert public_path == "/uploads/players/default-dir-test.jpg"

    dest = Path.join([:code.priv_dir(:cuevolution), "static", "uploads", "players"])
    assert File.exists?(Path.join(dest, "default-dir-test.jpg"))
  after
    File.rm(
      Path.join([:code.priv_dir(:cuevolution), "static/uploads/players/default-dir-test.jpg"])
    )
  end

  test "stores under a configured :uploads_dir instead — the volume-mounted path used in production",
       %{tmp_dir: tmp_dir} do
    Application.put_env(:cuevolution, :uploads_dir, tmp_dir)

    fixture = Path.join(:code.priv_dir(:cuevolution), "static/favicon.ico")

    assert {:ok, "/uploads/players/configured-dir-test.jpg"} =
             ProfilePicture.store(fixture, "configured-dir-test")

    assert File.exists?(Path.join([tmp_dir, "players", "configured-dir-test.jpg"]))
  end
end
