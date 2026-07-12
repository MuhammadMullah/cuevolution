defmodule Cuevolution.Accounts.ProfilePictureTest.FakeStorage do
  @moduledoc false
  @behaviour Cuevolution.Accounts.ProfilePicture.Storage
  @impl true
  def put(key, _body, _content_type), do: {:ok, "https://fake.example/#{key}"}
end

defmodule Cuevolution.Accounts.ProfilePictureTest.FailingStorage do
  @moduledoc false
  @behaviour Cuevolution.Accounts.ProfilePicture.Storage
  @impl true
  def put(_key, _body, _content_type), do: {:error, :some_failure}
end

defmodule Cuevolution.Accounts.ProfilePictureTest do
  # async: false — mutates the global :profile_picture_storage Application
  # env that every test in this file reads.
  use ExUnit.Case, async: false

  alias Cuevolution.Accounts.ProfilePicture
  alias Cuevolution.Accounts.ProfilePictureTest.FailingStorage
  alias Cuevolution.Accounts.ProfilePictureTest.FakeStorage

  @fixture Path.join(:code.priv_dir(:cuevolution), "static/favicon.ico")

  setup do
    on_exit(fn -> Application.delete_env(:cuevolution, :profile_picture_storage) end)
  end

  test "resizes and stores under the default (Local) backend, returning its public URL" do
    assert {:ok, "/uploads/players/default-backend-test.jpg"} =
             ProfilePicture.store(@fixture, "default-backend-test")

    dest =
      Path.join([:code.priv_dir(:cuevolution), "static/uploads/players/default-backend-test.jpg"])

    assert File.exists?(dest)
  after
    File.rm(
      Path.join([:code.priv_dir(:cuevolution), "static/uploads/players/default-backend-test.jpg"])
    )
  end

  test "delegates to whatever storage backend is configured" do
    Application.put_env(:cuevolution, :profile_picture_storage, FakeStorage)

    assert {:ok, "https://fake.example/players/fake-backend-test.jpg"} =
             ProfilePicture.store(@fixture, "fake-backend-test")
  end

  test "returns {:error, reason} instead of raising when the storage backend fails" do
    Application.put_env(:cuevolution, :profile_picture_storage, FailingStorage)

    assert {:error, :some_failure} = ProfilePicture.store(@fixture, "failing-backend-test")
  end
end
