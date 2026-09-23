defmodule Cuevolution.Competitions.StageGroupConfigTest do
  use ExUnit.Case, async: true

  alias Cuevolution.Competitions.StageGroupConfig

  test "accepts grassroots draw configuration defaults" do
    changeset =
      StageGroupConfig.changeset(%StageGroupConfig{}, %{
        stage_id: Ecto.UUID.generate(),
        category: "male",
        group_size: 8,
        advancer_count: 2,
        target_group_size: 8,
        minimum_group_size: 6,
        minimum_entrants: 4,
        extra_qualifier_count: 0
      })

    assert changeset.valid?
  end

  test "requires a non-negative extra qualifier count" do
    changeset =
      StageGroupConfig.changeset(%StageGroupConfig{}, %{
        stage_id: Ecto.UUID.generate(),
        category: "male",
        group_size: 8,
        advancer_count: 2,
        target_group_size: 8,
        minimum_group_size: 6,
        minimum_entrants: 4,
        extra_qualifier_count: -1
      })

    refute changeset.valid?
    assert "must be greater than or equal to 0" in errors_on(changeset).extra_qualifier_count
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
