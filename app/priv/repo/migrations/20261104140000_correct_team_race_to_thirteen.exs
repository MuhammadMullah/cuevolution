defmodule Cuevolution.Repo.Migrations.CorrectTeamRaceToThirteen do
  use Ecto.Migration

  # Circuit team matches are best of 25, which is won by the first side to 13.
  # They were drawn at race to 14, so the scoring panel let a frame be counted
  # past the win — a match could reach 14-9.
  #
  # Only the national team rounds are touched: the men's and ladies' brackets
  # and every venue- and region-scoped group are left exactly as they are.
  @national_team_rounds """
  SELECT r.id FROM rounds r
  JOIN groups g ON g.id = r.group_id
  WHERE g.category = 'team' AND g.region_id IS NULL AND g.venue_id IS NULL
  """

  def up do
    # A 14 is only safely a 13 if the other side never reached 13 — otherwise
    # lowering it would invent a draw, or flip the winner. Stop and let a human
    # look rather than guess at a result that has already been published.
    unsafe =
      repo().query!("""
      SELECT count(*) FROM match_results mr
      JOIN fixtures f ON f.id = mr.fixture_id
      WHERE f.round_id IN (#{@national_team_rounds})
        AND ((mr.score->>'a' = '14' AND (mr.score->>'b')::int >= 13)
          OR (mr.score->>'b' = '14' AND (mr.score->>'a')::int >= 13))
      """).rows

    case unsafe do
      [[0]] ->
        :ok

      [[n]] ->
        raise "#{n} team result(s) are 14 against 13 or more and cannot be corrected " <>
                "automatically — review them before running this migration"
    end

    execute """
    UPDATE rounds SET race_to = 13
    WHERE id IN (#{@national_team_rounds}) AND race_to = 14
    """

    for side <- ~w(a b) do
      execute """
      UPDATE match_results mr SET score = jsonb_set(mr.score, '{#{side}}', '13')
      FROM fixtures f
      WHERE f.id = mr.fixture_id
        AND f.round_id IN (#{@national_team_rounds})
        AND mr.score->>'#{side}' = '14'
      """

      execute """
      UPDATE fixtures SET live_score = jsonb_set(live_score, '{#{side}}', '13')
      WHERE round_id IN (#{@national_team_rounds})
        AND live_score->>'#{side}' = '14'
      """
    end
  end

  def down do
    # Deliberately not reversed: 13 is the correct race length, and putting
    # scores back to 14 would restore results that could not have happened.
    execute """
    UPDATE rounds SET race_to = 14
    WHERE id IN (#{@national_team_rounds}) AND race_to = 13
    """
  end
end
