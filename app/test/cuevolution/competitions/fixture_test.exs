defmodule Cuevolution.Competitions.FixtureTest do
  use ExUnit.Case, async: true

  alias Cuevolution.Competitions.{Fixture, StageParticipation}

  test "auto-generated fixtures do not require a venue or schedule" do
    participant_a = %StageParticipation{stage_id: Ecto.UUID.generate(), category: "male"}
    participant_b = %StageParticipation{stage_id: participant_a.stage_id, category: "male"}

    changeset =
      Fixture.auto_generate_changeset(
        %Fixture{},
        %{
          round_id: Ecto.UUID.generate(),
          participant_a_id: Ecto.UUID.generate(),
          participant_b_id: Ecto.UUID.generate(),
          match_id: "SP26-KIS01-MS-A-R1-M1"
        },
        %{participant_a: participant_a, participant_b: participant_b}
      )

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :status) == "scheduled"
  end

  test "manual fixtures still require venue and schedule" do
    participant_a = %StageParticipation{stage_id: Ecto.UUID.generate(), category: "male"}
    participant_b = %StageParticipation{stage_id: participant_a.stage_id, category: "male"}

    changeset =
      Fixture.changeset(
        %Fixture{},
        %{
          round_id: Ecto.UUID.generate(),
          participant_a_id: Ecto.UUID.generate(),
          participant_b_id: Ecto.UUID.generate()
        },
        %{participant_a: participant_a, participant_b: participant_b}
      )

    refute changeset.valid?
    assert "can't be blank" in errors_on(changeset).venue_id
    assert "can't be blank" in errors_on(changeset).scheduled_at
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
