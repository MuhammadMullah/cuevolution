-- ===========================================================================
-- Swap wrongly-placed Circuit players for the rightful ones.
--
-- Keeps the draw exactly as it is: the bracket slot does not move, only who
-- is standing in it. Each player owns one stage_participation row that
-- travels through the stages, so a swap is:
--
--   1. point the fixture slot at the rightful player's participation
--   2. move that participation up to the Circuit
--   3. move the wrong player's participation back to where the rightful
--      player was
--
-- Put the usernames in the VALUES list below. Left column is the player who
-- should NOT be there, right column is the one who should.
-- ===========================================================================


-- ─── STEP 1 ────────────────────────────────────────────────────────────────
-- Dry run. Changes nothing. Read every row before going near step 2.

WITH pairs(wrong_username, right_username) AS (
  VALUES
    ('Rojaa', 'Ndovu Tatu'),
    ('Enock', 'Robins')
)
SELECT
  pr.wrong_username,
  wp.first_name || ' ' || wp.last_name  AS leaving,
  ws.name                               AS leaving_is_at,
  pr.right_username,
  rp.first_name || ' ' || rp.last_name  AS arriving,
  rs.name                               AS arriving_is_at,
  f.match_id,
  CASE WHEN f.participant_a_id = pw.id THEN 'top' ELSE 'bottom' END AS slot,
  f.status,
  (f.result_id IS NOT NULL)             AS already_played,
  pw.category = pr2.category            AS same_category
FROM pairs pr
JOIN players wp              ON btrim(lower(wp.username)) = btrim(lower(pr.wrong_username))
JOIN players rp              ON btrim(lower(rp.username)) = btrim(lower(pr.right_username))
JOIN stage_participations pw ON pw.player_id = wp.id
JOIN stage_participations pr2 ON pr2.player_id = rp.id
JOIN stages ws               ON ws.id = pw.stage_id
JOIN stages rs               ON rs.id = pr2.stage_id
LEFT JOIN rounds cr          ON cr.stage_id = pw.stage_id
LEFT JOIN fixtures f         ON f.round_id = cr.id
                            AND (f.participant_a_id = pw.id OR f.participant_b_id = pw.id)
ORDER BY pr.wrong_username;


-- ─── STEP 2 ────────────────────────────────────────────────────────────────
-- The swap. Refuses to run on anything unexpected rather than guessing.

BEGIN;

CREATE TEMP TABLE swap ON COMMIT DROP AS
WITH pairs(wrong_username, right_username) AS (
  VALUES
    ('Rojaa', 'Ndovu Tatu'),
    ('Enock', 'Robins')
)
SELECT
  pr.wrong_username,
  pr.right_username,
  pw.id        AS wrong_participation_id,
  pr2.id       AS right_participation_id,
  pw.stage_id  AS circuit_stage_id,
  pr2.stage_id AS right_from_stage_id,
  pw.category  AS wrong_category,
  pr2.category AS right_category
FROM pairs pr
JOIN players wp               ON btrim(lower(wp.username)) = btrim(lower(pr.wrong_username))
JOIN players rp               ON btrim(lower(rp.username)) = btrim(lower(pr.right_username))
JOIN stage_participations pw  ON pw.player_id = wp.id
JOIN stage_participations pr2 ON pr2.player_id = rp.id;

DO $$
DECLARE
  expected int := 2;           -- keep in step with the VALUES list above
  n int;
  offender text;
BEGIN
  SELECT count(*) INTO n FROM swap;
  IF n <> expected THEN
    RAISE EXCEPTION 'resolved % swap(s), expected % — check the usernames', n, expected;
  END IF;

  -- The player leaving must actually be at the Circuit.
  SELECT string_agg(s.wrong_username, ', ') INTO offender
  FROM swap s JOIN stages st ON st.id = s.circuit_stage_id WHERE st.name <> 'Circuit';
  IF offender IS NOT NULL THEN
    RAISE EXCEPTION 'not at the Circuit: %', offender;
  END IF;

  -- The player arriving must not already be there.
  SELECT string_agg(s.right_username, ', ') INTO offender
  FROM swap s JOIN stages st ON st.id = s.right_from_stage_id WHERE st.name = 'Circuit';
  IF offender IS NOT NULL THEN
    RAISE EXCEPTION 'already at the Circuit: %', offender;
  END IF;

  -- Swapping across categories would put a man in the ladies' draw.
  SELECT string_agg(s.wrong_username, ', ') INTO offender
  FROM swap s WHERE s.wrong_category IS DISTINCT FROM s.right_category;
  IF offender IS NOT NULL THEN
    RAISE EXCEPTION 'category mismatch: %', offender;
  END IF;

  -- One unplayed fixture each. More than one means they have already
  -- advanced; a result means the match has been played, and neither can be
  -- undone by moving a name.
  SELECT string_agg(x.wrong_username, ', ') INTO offender
  FROM (
    SELECT s.wrong_username,
           count(f.id) FILTER (WHERE f.id IS NOT NULL)        AS fixtures,
           count(f.id) FILTER (WHERE f.result_id IS NOT NULL) AS played
    FROM swap s
    LEFT JOIN rounds r ON r.stage_id = s.circuit_stage_id
    LEFT JOIN fixtures f
      ON f.round_id = r.id
     AND (f.participant_a_id = s.wrong_participation_id
       OR f.participant_b_id = s.wrong_participation_id)
    GROUP BY s.wrong_username
  ) x
  WHERE x.fixtures <> 1 OR x.played > 0;
  IF offender IS NOT NULL THEN
    RAISE EXCEPTION 'not in exactly one unplayed fixture: %', offender;
  END IF;
END $$;

-- 1. The rightful player takes the slot.
-- Scoped to the Circuit on purpose. A player keeps ONE stage_participation
-- row that moves up through the stages, so this id is also on every
-- Grassroots and Regional match they ever played. Unscoped, this would hand
-- their whole history to the replacement.
UPDATE fixtures f
SET participant_a_id = CASE WHEN f.participant_a_id = s.wrong_participation_id
                            THEN s.right_participation_id ELSE f.participant_a_id END,
    participant_b_id = CASE WHEN f.participant_b_id = s.wrong_participation_id
                            THEN s.right_participation_id ELSE f.participant_b_id END,
    updated_at = now() AT TIME ZONE 'utc'
FROM swap s, rounds r
WHERE r.id = f.round_id
  AND r.stage_id = s.circuit_stage_id
  AND (f.participant_a_id = s.wrong_participation_id
    OR f.participant_b_id = s.wrong_participation_id);

-- 2. The rightful player moves up to the Circuit.
UPDATE stage_participations p
SET stage_id = s.circuit_stage_id, updated_at = now() AT TIME ZONE 'utc'
FROM swap s
WHERE p.id = s.right_participation_id;

-- 3. The wrong player goes back where the rightful player was.
UPDATE stage_participations p
SET stage_id = s.right_from_stage_id, updated_at = now() AT TIME ZONE 'utc'
FROM swap s
WHERE p.id = s.wrong_participation_id;

-- Read this before committing: the slot should now hold the rightful player.
SELECT f.match_id,
       ap.username AS top,
       bp.username AS bottom,
       f.status
FROM swap s
JOIN rounds r ON r.stage_id = s.circuit_stage_id
JOIN fixtures f ON f.round_id = r.id
               AND (f.participant_a_id = s.right_participation_id
                 OR f.participant_b_id = s.right_participation_id)
LEFT JOIN stage_participations sa ON sa.id = f.participant_a_id
LEFT JOIN players ap ON ap.id = sa.player_id
LEFT JOIN stage_participations sb ON sb.id = f.participant_b_id
LEFT JOIN players bp ON bp.id = sb.player_id;

-- COMMIT;   -- uncomment once the rows above look right
ROLLBACK;
