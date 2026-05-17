#!/usr/bin/env python3
"""Track word adds/removes across the wordlist `diff` branch.

Builds and incrementally updates an SQLite database of which upstream commit
added or removed each word in each en_*.txt dictionary.  Keyed by the upstream
commit hash (the `= <hash>` trailer in each diff-branch commit), so the DB
survives periodic rewrites of the diff branch itself.

Usage:
    util/track-words.py <repo-path> <db-path> [--branch diff] [--force]

`<repo-path>` is the directory containing `.git` (e.g. `./git`).
`--force` is required when verification finds existing rows that no longer
match the branch; it discards rows from the first divergent seq onward.
"""

import argparse
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

SCHEMA_VERSION = "1"
SCHEMA_SQL = Path(__file__).resolve().parent / "track-words.sql"

RS = "\x1e"
FS = "\x1f"

SKIP_RE = re.compile(
    r"^(NO CHANGE|DOC ONLY CHANGES|BUILD FAILED|BUILD SKIPPED)\.$",
    re.MULTILINE,
)
UPSTREAM_RE = re.compile(r"^= ([0-9a-f]{40})$", re.MULTILINE)
DIFF_HEADER_RE = re.compile(r"^diff --git a/(\S+) b/\S+")

# Tags we treat as releases.  Stored with the `diff/` prefix stripped so
# the canonical release name (e.g. "rel-2026.02.25", "scowl-7.1") shows
# up directly in `word_state.release_tag`.
RELEASE_TAG_RE = re.compile(r"^diff/(rel-.+|scowl-7\..+)$")


def init_db(conn: sqlite3.Connection, branch: str) -> None:
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript(SCHEMA_SQL.read_text())
    row = conn.execute("SELECT value FROM state WHERE key='branch'").fetchone()
    if row is None:
        conn.execute(
            "INSERT INTO state(key,value) VALUES('branch',?)", (branch,)
        )
        conn.execute(
            "INSERT INTO state(key,value) VALUES('schema_version',?)",
            (SCHEMA_VERSION,),
        )
    elif row[0] != branch:
        sys.exit(
            f"DB was previously populated from branch {row[0]!r}; "
            f"refusing to mix with {branch!r}.  Use a different DB."
        )


_CANONICAL_PICK = """
  SELECT dict, word, MIN(seq) AS seq FROM changes c
   WHERE op = (
     SELECT op FROM changes c2
      WHERE c2.dict = c.dict AND c2.word = c.word
      ORDER BY c2.seq DESC LIMIT 1
   )
"""


def mark_canonical(conn: sqlite3.Connection, start_seq: int, *,
                   full: bool = False) -> None:
    """(Re-)compute the canonical flag.

    There is exactly one canonical row per (dict, word): the earliest row
    whose op matches that pair's *current* state (op at MAX(seq)).

    If `full` is True (or start_seq == 0), recompute over the whole table.
    Otherwise recompute only for pairs that have any row at or after
    `start_seq` -- the append-only fast path.
    """
    if full or start_seq == 0:
        conn.execute("UPDATE changes SET canonical = 0 WHERE canonical = 1")
        conn.execute(f"""
            UPDATE changes SET canonical = 1
            WHERE (dict, word, seq) IN (
              {_CANONICAL_PICK}
              GROUP BY dict, word
            )
        """)
        return

    # Scoped path: clear canonical on pairs with new activity, then redo.
    conn.execute("""
        UPDATE changes SET canonical = 0
        WHERE canonical = 1
          AND EXISTS (
            SELECT 1 FROM changes c
            WHERE c.dict = changes.dict
              AND c.word = changes.word
              AND c.seq  >= ?
          )
    """, (start_seq,))
    conn.execute(f"""
        UPDATE changes SET canonical = 1
        WHERE (dict, word, seq) IN (
          {_CANONICAL_PICK}
            AND EXISTS (
              SELECT 1 FROM changes c3
              WHERE c3.dict = c.dict AND c3.word = c.word
                AND c3.seq  >= ?
            )
          GROUP BY dict, word
        )
    """, (start_seq,))


def git(repo: str, *args: str) -> str:
    res = subprocess.run(
        ["git", "-C", repo, *args],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return res.stdout


def walk_metadata(repo: str, branch: str):
    """Yield (diff_hash, upstream_hash, author_date, skipped) for every commit
    on the branch, oldest first.  Commits with no `= <hash>` trailer are
    skipped with a warning."""
    fmt = f"{RS}%H{FS}%aI{FS}%B{FS}"
    out = git(repo, "log", "--reverse", f"--format={fmt}", branch)
    for record in out.split(RS):
        if not record:
            continue
        try:
            diff_hash, author_date, body = record.split(FS, 2)
        except ValueError:
            continue
        body = body.rstrip(FS).rstrip("\n")
        m = UPSTREAM_RE.search(body)
        if not m:
            print(
                f"warning: commit {diff_hash[:8]} has no `= <hash>` trailer;"
                " skipping",
                file=sys.stderr,
            )
            continue
        upstream_hash = m.group(1)
        skipped = SKIP_RE.search(body) is not None
        yield diff_hash, upstream_hash, author_date, skipped


def find_divergence(real, stored):
    """Return seq of first divergence between walk and stored rows, or None."""
    for i, (s_seq, s_hash, s_date) in enumerate(stored):
        if i >= len(real):
            return s_seq
        _, w_hash, w_date = real[i]
        if w_hash != s_hash or w_date != s_date:
            return s_seq
    return None


def describe_divergence(real, stored, divergence):
    out = []
    for s_seq, s_hash, s_date in stored:
        if s_seq < divergence:
            continue
        i = s_seq
        if i < len(real):
            _, w_hash, w_date = real[i]
            out.append(
                f"seq {s_seq}: stored {s_hash[:8]}/{s_date}"
                f" -> walk {w_hash[:8]}/{w_date}"
            )
        else:
            out.append(
                f"seq {s_seq}: stored {s_hash[:8]}/{s_date} -> NOT IN BRANCH"
            )
    return out


def parse_diff(diff_text: str):
    """Yield (dict, op, word) for each +/- line under an en_*.txt file."""
    current_dict = None
    in_hunk = False
    for line in diff_text.splitlines():
        m = DIFF_HEADER_RE.match(line)
        if m:
            path = m.group(1)
            if path.startswith("en_") and path.endswith(".txt"):
                current_dict = path[:-4]
            else:
                current_dict = None
            in_hunk = False
            continue
        if current_dict is None:
            continue
        if line.startswith("@@"):
            in_hunk = True
            continue
        if not in_hunk:
            continue
        if line.startswith("+"):
            word = line[1:]
            if word:
                yield current_dict, "add", word
        elif line.startswith("-"):
            word = line[1:]
            if word:
                yield current_dict, "remove", word


def ingest(conn, repo, branch, new_commits, start_seq):
    """Stream `git log -p` for the new range and write commits + changes.

    `new_commits` is a list of (diff_hash, upstream_hash, author_date) in
    order, starting at `start_seq`.  Skipped commits are filtered out
    already and won't appear here."""
    if not new_commits:
        return

    expected = {
        diff_hash: (start_seq + i, upstream_hash, author_date)
        for i, (diff_hash, upstream_hash, author_date) in enumerate(new_commits)
    }

    first_new_diff_hash = new_commits[0][0]
    if start_seq == 0:
        range_args = [branch]
    else:
        range_args = [f"{first_new_diff_hash}^..{branch}"]

    fmt = f"{RS}%H{FS}%aI{FS}%B{FS}"
    proc = subprocess.run(
        ["git", "-C", repo, "log", "--reverse", "--no-renames",
         f"--format={fmt}", "-p", *range_args],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )

    seen = 0
    for record in proc.stdout.split(RS):
        if not record:
            continue
        try:
            diff_hash, author_date, rest = record.split(FS, 2)
        except ValueError:
            continue
        try:
            body_end = rest.index(FS)
        except ValueError:
            continue
        diff_text = rest[body_end + 1:]
        info = expected.get(diff_hash)
        if info is None:
            continue
        seq, upstream_hash, _expected_date = info
        conn.execute(
            "INSERT INTO commits(seq, hash, author_date) VALUES (?,?,?)",
            (seq, upstream_hash, author_date),
        )
        rows = [
            (seq, d, op, w) for (d, op, w) in parse_diff(diff_text)
        ]
        if rows:
            conn.executemany(
                "INSERT INTO changes(seq, dict, op, word) VALUES (?,?,?,?)",
                rows,
            )
        seen += 1

    if seen != len(new_commits):
        sys.exit(
            f"ingest mismatch: expected {len(new_commits)} commits in diff"
            f" stream, saw {seen}"
        )


def rebuild_tags(conn, repo, diff_hash_to_seq) -> int:
    """Repopulate `tags` table.  `diff_hash_to_seq` maps every diff-branch
    commit hash to the seq of the nearest non-skipped commit at-or-before it,
    so tags landing on a NO CHANGE / DOC ONLY commit still resolve."""
    conn.execute("DELETE FROM tags")
    fmt = f"%(refname:short){FS}%(*objectname){FS}%(objectname)"
    out = git(repo, "for-each-ref", "refs/tags", f"--format={fmt}")
    n = 0
    for line in out.splitlines():
        parts = line.split(FS)
        if len(parts) != 3:
            continue
        tag, peeled, raw = parts
        m = RELEASE_TAG_RE.match(tag)
        if not m:
            continue
        commit_hash = peeled or raw
        if not commit_hash:
            continue
        seq = diff_hash_to_seq.get(commit_hash)
        if seq is None:
            continue
        conn.execute("INSERT INTO tags(tag, seq) VALUES (?, ?)", (m.group(1), seq))
        n += 1
    return n


def run(conn, args):
    init_db(conn, args.branch)

    walked = list(walk_metadata(args.repo_path, args.branch))
    real = [(dh, uh, ad) for (dh, uh, ad, sk) in walked if not sk]

    # diff-branch hash -> seq of nearest non-skipped commit at-or-before.
    # Used for tags landing on NO CHANGE / DOC ONLY commits.
    diff_hash_to_seq = {}
    last_real_seq = None
    real_i = 0
    for dh, _, _, sk in walked:
        if not sk:
            diff_hash_to_seq[dh] = real_i
            last_real_seq = real_i
            real_i += 1
        elif last_real_seq is not None:
            diff_hash_to_seq[dh] = last_real_seq
    stored = list(
        conn.execute("SELECT seq, hash, author_date FROM commits ORDER BY seq")
    )

    divergence = find_divergence(real, stored)

    if divergence is not None:
        problems = describe_divergence(real, stored, divergence)
        msg_lines = ["verification failed:"]
        msg_lines.extend("  " + p for p in problems[:10])
        if len(problems) > 10:
            msg_lines.append(f"  ... ({len(problems) - 10} more)")
        print("\n".join(msg_lines), file=sys.stderr)
        if not args.force:
            print(
                "Rerun with --force to discard divergent commits and reingest.",
                file=sys.stderr,
            )
            sys.exit(1)
        print(
            f"--force: deleting commits with seq >= {divergence}",
            file=sys.stderr,
        )
        conn.execute("DELETE FROM commits WHERE seq >= ?", (divergence,))
        next_seq = divergence
        forced_rewind = True
    else:
        next_seq = len(stored)
        forced_rewind = False

    new_commits = real[next_seq:]
    ingest(conn, args.repo_path, args.branch, new_commits, next_seq)
    if new_commits or forced_rewind:
        # A rewind can flip a pair's current state without touching any
        # row at seq >= next_seq, so the scoped recompute would miss it.
        mark_canonical(conn, next_seq, full=forced_rewind)

    n_tags = rebuild_tags(conn, args.repo_path, diff_hash_to_seq)

    print(
        f"commits: {len(real)} (was {len(stored)}, "
        f"+{len(new_commits)} new); tags: {n_tags}",
        file=sys.stderr,
    )


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("repo_path", help="path to repository (containing .git)")
    p.add_argument("db_path", help="path to SQLite database file")
    p.add_argument("--branch", default="diff", help="branch to track (default: diff)")
    p.add_argument(
        "--force",
        action="store_true",
        help="discard divergent commits and rebuild from divergence point",
    )
    args = p.parse_args()

    conn = sqlite3.connect(args.db_path)
    try:
        run(conn, args)
        conn.commit()
    except BaseException:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
