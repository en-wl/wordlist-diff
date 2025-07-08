export DBNAME=scowl

export PGVER=11
export PGBINDIR=/usr/lib/postgresql/11/bin

export PATH="$PGBINDIR":"$PATH"

export DBROOT=/home/kevina/wordlist/diff/psqldb

export PGDIR="$DBROOT"/scowl
export PGHOST="$DBROOT"
export PGPORT=${PGPORT:-5437}

alias psql=`which psql`
pgctl () {
    pg_ctl -D "$PGDIR" -l "$PGDIR"/log "$@"
}
