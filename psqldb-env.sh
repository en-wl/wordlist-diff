# set this to the absolute path of the root directly you are running the
# scripts from.
ROOTDIR="${HOME}/wordlist/diff/"

export DBNAME=scowl

export PGVER=18
export PGBINDIR=/usr/lib/postgresql/18/bin

export PATH="$PGBINDIR":"$PATH"

export DBROOT="$ROOTDIR"/psqldb

export PGDIR="$DBROOT"/scowl
export PGHOST="$DBROOT"
export PGPORT=${PGPORT:-5437}

alias psql=$(command -v psql)

pgctl () {
	pg_ctl -D "$PGDIR" -l "$PGDIR"/log "$@"
}
