#!/bin/sh

. ../psqldb-env.sh

set -e

export LC_ALL=C.UTF-8

./mk-list en_US 60 --encoding utf-8 | sort -u > en_US-60.new

psql scowl <<EOF
drop schema if exists v2 cascade;
EOF

( cd postgresql && sh import.sh scowl v2 )

if grep -q 'size' postgresql/schema.sql
then
    rm -f scowl-new.db
    ./scowl --db scowl-new.db import < data/basic
    ./scowl --db scowl-new.db merge < data/coca
    ./scowl --db scowl-new.db merge < data/signature
    ./scowl --db scowl-new.db merge < data/extra
    SCOWL_DB=scowl-new.db ./mk-list en_US 60 --encoding utf-8 > added-words
    psql scowl -f comp/comp-v2.sql
else
    psql scowl -f comp/comp-v1.sql
fi

comp/comp-report.py > comp-60.txt
