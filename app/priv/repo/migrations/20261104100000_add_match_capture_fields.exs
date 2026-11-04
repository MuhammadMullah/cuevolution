defmodule Cuevolution.Repo.Migrations.AddMatchCaptureFields do
  use Ecto.Migration

  # The last three fields on the brief's "match data to capture" list. All are
  # marked optional there, and none feeds the points or the standings — they
  # are for scheduling and for the highlight stats.
  #
  # The rest of that list is already stored: the match reference, the round and
  # its bracket side, both players, the score, the winner, and the result type
  # (derived from `bye`, `walkover_kind` and `status` — see
  # `Competitions.result_type/1`). "Circuit" is the one field still missing,
  # and it waits on the three legs existing as entities.
  def change do
    alter table(:fixtures) do
      add :table_number, :integer
      add :ended_at, :utc_datetime
      add :break_and_clears, :integer
    end

    create constraint(:fixtures, :fixtures_table_number_positive,
             check: "table_number IS NULL OR table_number > 0"
           )

    create constraint(:fixtures, :fixtures_break_and_clears_not_negative,
             check: "break_and_clears IS NULL OR break_and_clears >= 0"
           )
  end
end
