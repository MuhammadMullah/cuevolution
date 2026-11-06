WITH pairs(wrong_username, right_username) AS (
  VALUES
    ('Rojaa', 'Ndovu Tatu'),
    ('Enock', 'Robins')
),
resolved AS (
  SELECT pr.wrong_username, pr.right_username,
         pw.id        AS wrong_pid,
         pr2.id       AS right_pid,
         pw.stage_id  AS circuit_stage_id,
         pr2.stage_id AS from_stage_id,
         f.id         AS fixture_id
  FROM pairs pr
  JOIN players wp               ON btrim(lower(wp.username))  = btrim(lower(pr.wrong_username))
  JOIN players rp               ON btrim(lower(rp.username))  = btrim(lower(pr.right_username))
  JOIN stage_participations pw  ON pw.player_id  = wp.id
  JOIN stage_participations pr2 ON pr2.player_id = rp.id
  -- Every safety rule is a join condition, so anything unexpected yields no
  -- row and therefore changes nothing: the leaver must be at the Circuit,
  -- the arriver must not be, categories must match, and the match must be
  -- unplayed. Scoped to Circuit rounds — a participation id is also on every
  -- earlier-stage match that player ever played.
  JOIN stages cs ON cs.id = pw.stage_id  AND cs.name =  'Circuit'
  JOIN stages fs ON fs.id = pr2.stage_id AND fs.name <> 'Circuit'
  JOIN rounds r  ON r.stage_id = pw.stage_id
  JOIN fixtures f ON f.round_id = r.id
                 AND f.result_id IS NULL
                 AND (f.participant_a_id = pw.id OR f.participant_b_id = pw.id)
  WHERE pw.category = pr2.category
),
-- All or nothing: if either pair fails to resolve, neither is applied.
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
