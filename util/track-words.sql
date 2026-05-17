-- Schema and views for util/track-words.py.
--
-- Idempotent: tables / indexes use CREATE ... IF NOT EXISTS; views use
-- DROP/CREATE so they get refreshed on every run.  Running this against
-- an existing DB does not touch any table or its data.
--
-- A row in `changes` is marked `canonical = 1` when it is the earliest
-- (smallest-seq) row for its (dict, word) whose op matches the current
-- state -- i.e. the op of the row at the highest seq for that pair.
-- There is therefore exactly one canonical row per (dict, word):
--   * if currently added: canonical = first add
--   * if currently removed: canonical = first remove
-- Later flapping is preserved in the table but ignored by `word_state`.

CREATE TABLE IF NOT EXISTS commits (
  seq         INTEGER PRIMARY KEY,
  hash        TEXT NOT NULL UNIQUE,
  author_date TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS changes (
  seq       INTEGER NOT NULL REFERENCES commits(seq) ON DELETE CASCADE,
  dict      TEXT    NOT NULL,
  op        TEXT    NOT NULL CHECK (op IN ('add','remove')),
  word      TEXT    NOT NULL,
  canonical INTEGER NOT NULL DEFAULT 0 CHECK (canonical IN (0, 1)),
  PRIMARY KEY (word, dict, seq)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS changes_by_seq ON changes(seq);

CREATE TABLE IF NOT EXISTS tags (
  tag TEXT PRIMARY KEY,
  seq INTEGER NOT NULL REFERENCES commits(seq) ON DELETE CASCADE
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS state (
  key TEXT PRIMARY KEY,
  value TEXT
) WITHOUT ROWID;

-- ----------------------------------------------------------------------
-- Views
-- ----------------------------------------------------------------------

DROP VIEW IF EXISTS word_state;
CREATE VIEW word_state AS
SELECT
  ch.dict,
  ch.word,
  ch.op AS current_state,
  ch.seq,
  co.hash,
  co.author_date,
  (SELECT t.tag FROM tags t
     WHERE t.seq >= ch.seq
     ORDER BY t.seq ASC LIMIT 1) AS release_tag
FROM changes ch
JOIN commits co ON co.seq = ch.seq
WHERE ch.canonical = 1;
