defmodule Cuevolution.Accounts.AdminActionLogTest do
  use ExUnit.Case, async: true

  alias Cuevolution.Accounts.AdminActionLog

  test "requires an admin actor for admin entries" do
    changeset = AdminActionLog.changeset(%AdminActionLog{}, %{actor_type: "admin"})

    refute changeset.valid?
    assert "is required for admin actions" in errors_on(changeset).admin_id
  end

  test "allows a system entry without an admin actor" do
    changeset =
      AdminActionLog.changeset(%AdminActionLog{}, %{
        actor_type: "system",
        action_type: "deadline_walkover",
        entity_type: "Cuevolution.Competitions.Fixture",
        entity_id: Ecto.UUID.generate()
      })

    assert changeset.valid?
  end

  test "rejects an admin actor on a system entry" do
    changeset =
      AdminActionLog.changeset(%AdminActionLog{}, %{
        actor_type: "system",
        admin_id: Ecto.UUID.generate(),
        action_type: "deadline_walkover",
        entity_type: "Cuevolution.Competitions.Fixture",
        entity_id: Ecto.UUID.generate()
      })

    refute changeset.valid?
    assert "must be empty for system actions" in errors_on(changeset).admin_id
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
