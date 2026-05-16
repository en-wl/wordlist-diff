-- Schema and views for util/track-words.py.
--
-- Idempotent: tables are CREATE TABLE IF NOT EXISTS; views are
-- DROP/CREATE so they get refreshed on every run.  Running this against
-- an existing DB will not touch any table or its data.

CREATE TABLE IF NOT EXISTS commits (
  seq         INTEGER PRIMARY KEY,
  hash        TEXT NOT NULL UNIQUE,
  author_date TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS changes (
  seq  INTEGER NOT NULL REFERENCES commits(seq) ON DELETE CASCADE,
  dict TEXT NOT NULL,
  op   TEXT NOT NULL CHECK (op IN ('add','remove')),
  word TEXT NOT NULL,
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

-- One row per (dict, word) ever touched.  Collapses add/remove flapping
-- by reporting the *current* op separately from the *first-add* commit.
-- `release_tag` is the most recent release that included the first-add
-- commit (null if the word was added after the latest tagged release).
DROP VIEW IF EXISTS word_state;
CREATE VIEW word_state AS
SELECT
  agg.dict,
  agg.word,
  (SELECT op FROM changes c
     WHERE c.dict = agg.dict AND c.word = agg.word
     ORDER BY c.seq DESC LIMIT 1)         AS current_state,
  agg.first_add_seq,
  fc.hash                                 AS first_add_hash,
  fc.author_date                          AS first_add_date,
  (SELECT t.tag FROM tags t
     WHERE t.seq >= agg.first_add_seq
     ORDER BY t.seq DESC LIMIT 1)         AS release_tag
FROM (
  SELECT dict, word,
         MIN(CASE WHEN op = 'add' THEN seq END) AS first_add_seq
  FROM changes
  GROUP BY dict, word
) AS agg
LEFT JOIN commits fc ON fc.seq = agg.first_add_seq;
