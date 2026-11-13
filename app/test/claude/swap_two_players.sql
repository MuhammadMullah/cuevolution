-- Exchange two players who are already in the Circuit draw, between their
-- two fixtures. Each keeps the slot position they are in; only which match
-- they are in changes. Nobody's stage moves — both are already at the
-- Circuit.
WITH people(player_id, label) AS (
  VALUES
    ('PASTE_GABRIEL_ID'::uuid, 'first'),
    ('PASTE_ROBERT_ID'::uuid,  'second')
),
spots AS (
  SELECT pe.label,
         sp.id AS pid,
         f.id  AS fixture_id,
         CASE WHEN f.participant_a_id = sp.id THEN 'a' ELSE 'b' END AS slot
  FROM people pe
  JOIN stage_participations sp ON sp.player_id = pe.player_id
  JOIN stages s ON s.id = sp.stage_id AND s.name = 'Circuit'
  -- Circuit rounds only, and only matches not yet played.
  JOIN rounds r   ON r.stage_id = sp.stage_id
  JOIN fixtures f ON f.round_id = r.id
                 AND f.result_id IS NULL
                 AND (f.participant_a_id = sp.id OR f.participant_b_id = sp.id)
),
-- Exactly one spot each, and two distinct people: anything else changes
-- nothing. (Counting distinct labels as well as rows, so one player holding
-- two spots can never look like a valid pair.)
gate AS (
  SELECT * FROM spots
  WHERE (SELECT count(*) FROM spots) = 2
    AND (SELECT count(DISTINCT label) FROM spots) = 2
    AND (SELECT count(DISTINCT fixture_id) FROM spots) = 2
),
-- Each spot receives the other person.
moves AS (
  SELECT mine.fixture_id, mine.slot, theirs.pid AS incoming
  FROM gate mine
  JOIN gate theirs ON theirs.label <> mine.label
),
applied AS (
  UPDATE fixtures f
  SET participant_a_id = CASE WHEN m.slot = 'a' THEN m.incoming ELSE f.participant_a_id END,
      participant_b_id = CASE WHEN m.slot = 'b' THEN m.incoming ELSE f.participant_b_id END,
      updated_at = now() AT TIME ZONE 'utc'
  FROM moves m
  WHERE f.id = m.fixture_id
  RETURNING f.match_id
)
SELECT (SELECT count(*) FROM spots)   AS spots_found,
       (SELECT count(*) FROM gate)    AS gate_passed,
       (SELECT count(*) FROM applied) AS fixtures_changed;
