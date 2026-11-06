-- Keyed on player id, not username. The username column in this database
-- carries stray whitespace — 'Enock' and 'Enock ' are two different players,
-- and trimming to cope with one of them made the other ambiguous. An id is
-- an id.
WITH pairs(wrong_player_id, right_player_id) AS (
  VALUES
    ('PASTE_ROJAA_ID'::uuid,           'PASTE_NDOVU_TATU_ID'::uuid),
    ('PASTE_ENOCK_CHERUIYOT_ID'::uuid, 'PASTE_ROBINS_ID'::uuid)
),
resolved AS (
  SELECT pw.id        AS wrong_pid,
         pr2.id       AS right_pid,
         pw.stage_id  AS circuit_stage_id,
         pr2.stage_id AS from_stage_id,
         f.id         AS fixture_id
  FROM pairs pr
  JOIN stage_participations pw  ON pw.player_id  = pr.wrong_player_id
  JOIN stage_participations pr2 ON pr2.player_id = pr.right_player_id
  -- Each safety rule is a join condition, so anything unexpected yields no
  -- row and changes nothing.
  JOIN stages cs ON cs.id = pw.stage_id  AND cs.name =  'Circuit'
  JOIN stages fs ON fs.id = pr2.stage_id AND fs.name <> 'Circuit'
  -- Circuit rounds only: a participation id is also on every earlier-stage
  -- match that player ever played.
  JOIN rounds r   ON r.stage_id = pw.stage_id
  JOIN fixtures f ON f.round_id = r.id
                 AND f.result_id IS NULL
                 AND (f.participant_a_id = pw.id OR f.participant_b_id = pw.id)
  WHERE pw.category = pr2.category
),
gate AS (
  SELECT * FROM resolved WHERE (SELECT count(*) FROM resolved) = 2
),
slot AS (
  UPDATE fixtures f
  SET participant_a_id = CASE WHEN f.participant_a_id = g.wrong_pid
                              THEN g.right_pid ELSE f.participant_a_id END,
      participant_b_id = CASE WHEN f.participant_b_id = g.wrong_pid
                              THEN g.right_pid ELSE f.participant_b_id END,
      updated_at = now() AT TIME ZONE 'utc'
  FROM gate g WHERE f.id = g.fixture_id
  RETURNING f.match_id
),
promote AS (
  UPDATE stage_participations p
  SET stage_id = g.circuit_stage_id, updated_at = now() AT TIME ZONE 'utc'
  FROM gate g WHERE p.id = g.right_pid
  RETURNING p.id
),
demote AS (
  UPDATE stage_participations p
  SET stage_id = g.from_stage_id, updated_at = now() AT TIME ZONE 'utc'
  FROM gate g WHERE p.id = g.wrong_pid
  RETURNING p.id
)
SELECT (SELECT count(*) FROM resolved) AS resolved,
       (SELECT count(*) FROM gate)     AS applied,
       (SELECT count(*) FROM slot)     AS slots_changed,
       (SELECT count(*) FROM promote)  AS moved_up,
       (SELECT count(*) FROM demote)   AS moved_back;
