-- Every bracket match whose onward slot holds somebody other than the
-- recorded winner (or loser). Caused by correcting a result from a screen
-- that did not re-point the bracket.
--
-- Read-only. `should_be` is who belongs in that slot.
SELECT f.match_id        AS decided_match,
       onward.match_id   AS onward_match,
       CASE WHEN e.edge = 'winner' THEN f.winner_to_side ELSE f.loser_to_side END AS slot,
       e.edge,
       sitting_p.first_name || ' ' || sitting_p.last_name AS currently_sitting_there,
       should_p.first_name  || ' ' || should_p.last_name  AS should_be,
       onward.status      AS onward_status,
       (onward.result_id IS NOT NULL) AS onward_already_played
FROM fixtures f
JOIN match_results mr ON mr.id = f.result_id
JOIN rounds r  ON r.id = f.round_id AND r.knockout_bracket_id IS NOT NULL
CROSS JOIN LATERAL (VALUES ('winner'), ('loser')) AS e(edge)
JOIN fixtures onward
  ON onward.id = CASE WHEN e.edge = 'winner' THEN f.winner_to_fixture_id
                                             ELSE f.loser_to_fixture_id END
-- who the result says should be there
CROSS JOIN LATERAL (
  SELECT CASE WHEN e.edge = 'winner' THEN mr.winner_participation_id
              WHEN f.participant_a_id = mr.winner_participation_id THEN f.participant_b_id
              ELSE f.participant_a_id END AS pid
) AS expected
-- who actually is
CROSS JOIN LATERAL (
  SELECT CASE WHEN (CASE WHEN e.edge = 'winner' THEN f.winner_to_side ELSE f.loser_to_side END) = 'a'
              THEN onward.participant_a_id ELSE onward.participant_b_id END AS pid
) AS actual
LEFT JOIN stage_participations ssp ON ssp.id = actual.pid
LEFT JOIN players sitting_p        ON sitting_p.id = ssp.player_id
LEFT JOIN stage_participations esp ON esp.id = expected.pid
LEFT JOIN players should_p         ON should_p.id = esp.player_id
WHERE actual.pid IS DISTINCT FROM expected.pid
ORDER BY f.match_id;
