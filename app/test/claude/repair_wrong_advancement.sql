-- Re-points every onward slot at whoever the recorded result says belongs
-- there. Atomic, and fixes only matches that have not themselves been
-- played — once an onward match has a result, moving a name would rewrite
-- something that actually happened, so those are left for a human.
WITH mismatches AS (
  SELECT onward.id AS onward_id,
         CASE WHEN e.edge = 'winner' THEN f.winner_to_side ELSE f.loser_to_side END AS slot,
         expected.pid AS expected_pid,
         (onward.result_id IS NOT NULL) AS onward_played
  FROM fixtures f
  JOIN match_results mr ON mr.id = f.result_id
  JOIN rounds r ON r.id = f.round_id AND r.knockout_bracket_id IS NOT NULL
  CROSS JOIN LATERAL (VALUES ('winner'), ('loser')) AS e(edge)
  JOIN fixtures onward
    ON onward.id = CASE WHEN e.edge = 'winner' THEN f.winner_to_fixture_id
                                               ELSE f.loser_to_fixture_id END
  CROSS JOIN LATERAL (
    SELECT CASE WHEN e.edge = 'winner' THEN mr.winner_participation_id
                WHEN f.participant_a_id = mr.winner_participation_id THEN f.participant_b_id
                ELSE f.participant_a_id END AS pid
  ) AS expected
  CROSS JOIN LATERAL (
    SELECT CASE WHEN (CASE WHEN e.edge = 'winner' THEN f.winner_to_side ELSE f.loser_to_side END) = 'a'
                THEN onward.participant_a_id ELSE onward.participant_b_id END AS pid
  ) AS actual
  WHERE actual.pid IS DISTINCT FROM expected.pid
),
-- One row per onward fixture, so a match whose BOTH feeders were corrected
-- is fixed in a single update rather than half-fixed.
fixes AS (
  SELECT onward_id,
         (array_agg(expected_pid) FILTER (WHERE slot = 'a'))[1] AS new_a,
         (array_agg(expected_pid) FILTER (WHERE slot = 'b'))[1] AS new_b
  FROM mismatches
  WHERE NOT onward_played
  GROUP BY onward_id
),
applied AS (
  UPDATE fixtures o
  SET participant_a_id = COALESCE(f.new_a, o.participant_a_id),
      participant_b_id = COALESCE(f.new_b, o.participant_b_id),
      updated_at = now() AT TIME ZONE 'utc'
  FROM fixes f
  WHERE o.id = f.onward_id
  RETURNING o.match_id
)
SELECT (SELECT count(*) FROM mismatches)                          AS mismatches_found,
       (SELECT count(*) FROM mismatches WHERE onward_played)      AS left_alone_already_played,
       (SELECT count(*) FROM applied)                             AS fixtures_repaired;
