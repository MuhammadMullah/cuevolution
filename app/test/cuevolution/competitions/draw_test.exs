defmodule Cuevolution.Competitions.DrawTest do
  use ExUnit.Case, async: true

  alias Cuevolution.Competitions.Draw

  test "accepts the draft defaults and configured individual category" do
    changeset =
      Draw.changeset(%Draw{}, %{
        stage_id: Ecto.UUID.generate(),
        venue_id: Ecto.UUID.generate(),
        category: "male",
        formula_group_count: 2
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :state) == "draft"
  end

  test "rejects team draws and non-positive group counts" do
    changeset =
      Draw.changeset(%Draw{}, %{
        stage_id: Ecto.UUID.generate(),
        venue_id: Ecto.UUID.generate(),
        category: "team",
        formula_group_count: 0
      })

    refute changeset.valid?
    assert "is invalid" in errors_on(changeset).category
    assert "must be greater than 0" in errors_on(changeset).formula_group_count
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
