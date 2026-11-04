defmodule Cuevolution.Repo.Migrations.AddDoubleEliminationToBrackets do
  use Ecto.Migration

  @moduledoc """
  Lets the Circuit stage hold a full double-elimination bracket (spec 014).

  Two things the existing knockout model can't express:

    * A round has no side, no order and no race length. The Circuit format
      needs all three — a winners' and a losers' side that interleave, and
      races that differ per round (men: 6 all through, 5 on the losers' side,
      7 in the final).
    * A fixture records where its *winner* goes only implicitly, by the next
      round existing, and has nowhere at all to record where its *loser* goes.
      Double elimination is entirely about the loser's path.

  The whole bracket is also generated up front, so a fixture has to be able to
  exist before its players are known ("winner of match 9"). The two
  participant columns therefore become nullable — but only for bracket
  fixtures: `non_bracket_participants_present` below keeps the NOT NULL
  guarantee for every fixture that isn't in a bracket slot, so the
  Grassroots/Regional round-robin path is unchanged.
  """

  def change do
    alter table(:rounds) do
      add :bracket_side, :string
      add :sequence, :integer
      add :race_to, :integer
    end

    create constraint(:rounds, :bracket_side_must_be_valid,
             check: "bracket_side IS NULL OR bracket_side IN ('winners', 'losers', 'knockout')"
           )

    create constraint(:rounds, :race_to_must_be_positive, check: "race_to IS NULL OR race_to > 0")

    create unique_index(:rounds, [:knockout_bracket_id, :sequence],
             where: "knockout_bracket_id IS NOT NULL AND sequence IS NOT NULL",
             name: :rounds_bracket_sequence_unique_index
           )

    alter table(:fixtures) do
      add :slot, :integer
      add :bye, :boolean, null: false, default: false

      add :winner_to_fixture_id,
          references(:fixtures, type: :binary_id, on_delete: :nilify_all)

      add :winner_to_side, :string

      add :loser_to_fixture_id,
          references(:fixtures, type: :binary_id, on_delete: :nilify_all)

      add :loser_to_side, :string

      modify :participant_a_id, :binary_id, null: true, from: {:binary_id, null: false}
      modify :participant_b_id, :binary_id, null: true, from: {:binary_id, null: false}
    end

    create index(:fixtures, [:winner_to_fixture_id])
    create index(:fixtures, [:loser_to_fixture_id])

    create unique_index(:fixtures, [:round_id, :slot],
             where: "slot IS NOT NULL",
             name: :fixtures_round_slot_unique_index
           )

    create constraint(:fixtures, :routing_sides_must_be_valid,
             check: """
             (winner_to_side IS NULL OR winner_to_side IN ('a', 'b')) AND
             (loser_to_side IS NULL OR loser_to_side IN ('a', 'b'))
             """
           )

    # A routing target and the slot it lands in are meaningless apart, so they
    # are written together or not at all.
    create constraint(:fixtures, :routing_target_needs_side,
             check: """
             (winner_to_fixture_id IS NULL) = (winner_to_side IS NULL) AND
             (loser_to_fixture_id IS NULL) = (loser_to_side IS NULL)
             """
           )

    # Every fixture that isn't a bracket slot still has to carry both
    # participants, exactly as before. (venue_id and scheduled_at have been
    # nullable since the draws work in September — a fixture is drawn before
    # it is given a table and a time — so they are not asserted here.)
    create constraint(:fixtures, :non_bracket_participants_present,
             check: """
             slot IS NOT NULL OR
               (participant_a_id IS NOT NULL AND participant_b_id IS NOT NULL)
             """
           )
  end
end
