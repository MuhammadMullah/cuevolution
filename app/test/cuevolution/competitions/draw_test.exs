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

  test "accepts a region-scoped team draw" do
    changeset =
      Draw.changeset(%Draw{}, %{
        stage_id: Ecto.UUID.generate(),
        region_id: Ecto.UUID.generate(),
        category: "team",
        formula_group_count: 2
      })

    assert changeset.valid?
  end

  test "rejects an invalid category and non-positive group counts" do
    changeset =
      Draw.changeset(%Draw{}, %{
        stage_id: Ecto.UUID.generate(),
        venue_id: Ecto.UUID.generate(),
        category: "doubles",
        formula_group_count: 0
      })

    refute changeset.valid?
    assert "is invalid" in errors_on(changeset).category
    assert "must be greater than 0" in errors_on(changeset).formula_group_count
  end

  test "rejects a draw with neither a venue nor a region" do
    changeset =
      Draw.changeset(%Draw{}, %{
        stage_id: Ecto.UUID.generate(),
        category: "male",
        formula_group_count: 2
      })

    refute changeset.valid?
    assert "either a venue or a region must be set" in errors_on(changeset).venue_id
  end

  test "rejects a draw with both a venue and a region" do
    changeset =
      Draw.changeset(%Draw{}, %{
        stage_id: Ecto.UUID.generate(),
        venue_id: Ecto.UUID.generate(),
        region_id: Ecto.UUID.generate(),
        category: "male",
        formula_group_count: 2
      })

    refute changeset.valid?
    assert "cannot set both a venue and a region" in errors_on(changeset).venue_id
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
