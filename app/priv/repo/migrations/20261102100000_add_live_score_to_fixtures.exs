defmodule Cuevolution.Repo.Migrations.AddLiveScoreToFixtures do
  use Ecto.Migration

  @moduledoc """
  A running frame count for a match that is being played right now.

  `match_results` only exists once a match is over, so until this there was
  nowhere to put "6–6, deciding frame" while the tournament director watches
  it happen. That is the whole point of the live bracket: the TD taps a frame
  as it is won and every spectator's bracket updates.

  Deliberately a loose map rather than two integer columns — it carries
  `%{"a" => n, "b" => n}` today, and a frame-by-frame breakdown would fit the
  same column without another migration. The authoritative final score still
  lands in `match_results.score` when the match is recorded; this column is
  working state and is cleared at that point.
  """

  def change do
    alter table(:fixtures) do
      add :live_score, :map
    end
  end
end
