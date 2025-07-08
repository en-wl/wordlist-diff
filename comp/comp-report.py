#!/usr/bin/python3

import psycopg2
import psycopg2.extras
import sys
from sys import stdout, stderr, stdin
import os

p_conn = psycopg2.connect(dbname='scowl', cursor_factory=psycopg2.extras.NamedTupleCursor)

cur = p_conn.cursor()

def dump(header):
    prevNote = None
    cnt = 0
    for word, note in cur:
        if note == 'possessive':
            continue
        if note is None:
            note = 'unclassified'
        if note != prevNote:
            if cnt > 0:
                stdout.write(f"total: {cnt}\n\n")
                cnt = 0
            stdout.write(f"{header}, {note}:\n")
            prevNote = note
        cnt += 1
        stdout.write(f"  {word}\n")
    if cnt > 0:
        stdout.write(f"total: {cnt}\n\n")

cur.execute('select new,note from working.comm where not ok and old is null order by note nulls last, new collate "ucs_basic"')
dump("New words, NOT OK")

cur.execute('select old,note from working.comm where not ok and new is null order by note nulls last, old collate "ucs_basic"')
dump("Missing words, NOT OK")

cur.execute('select new,note from working.comm where ok is null and old is null order by note nulls first, new collate "ucs_basic"')
dump("New words")

cur.execute('select old,note from working.comm where ok is null and new is null order by note nulls first, old collate "ucs_basic"')
dump("Missing words")

cur.execute('select new,note from working.comm where ok and old is null order by note nulls first, new collate "ucs_basic"')
dump("New words, ok")

cur.execute('select old,note from working.comm where ok and new is null order by note nulls first, old collate "ucs_basic"')
dump("Missing words, ok")


