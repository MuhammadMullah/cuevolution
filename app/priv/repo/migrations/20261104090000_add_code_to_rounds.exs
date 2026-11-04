defmodule Cuevolution.Repo.Migrations.AddCodeToRounds do
  use Ecto.Migration

  # The bracket engine names every round with a short code — W1, L4, R32, SF,
  # F — and the SP Points rules are written in terms of them: "out in LB R4 is
  # 9 points", "3 a win from the last 32". Only the display name was persisted,
  # so the points engine had to infer the stage by matching on prose. The code
  # is the stable identity; the name is for people.
  #
  # Null for the round-robin rounds at Grassroots, Regional and the Circuit team
  # event, which have no bracket position.
  def up do
    alter table(:rounds) do
      add :code, :string
    end

    # Backfill the brackets already drawn, from the names the engine produced.
    execute """
    UPDATE rounds SET code =
      CASE
        WHEN name = 'Final' THEN 'F'
        WHEN name = 'Semifinals' THEN 'SF'
        WHEN name = 'Quarterfinals' THEN 'QF'
        WHEN name LIKE 'Round of %' THEN 'R' || substring(name from 'Round of ([0-9]+)')
        WHEN name LIKE 'Winners Round %' THEN 'W' || substring(name from 'Winners Round ([0-9]+)')
        WHEN name LIKE 'Losers Round %' THEN 'L' || substring(name from 'Losers Round ([0-9]+)')
      END
    WHERE knockout_bracket_id IS NOT NULL
    """

    create index(:rounds, [:knockout_bracket_id, :code])
  end

  def down do
    drop index(:rounds, [:knockout_bracket_id, :code])

    alter table(:rounds) do
      remove :code
    end
  end
end
