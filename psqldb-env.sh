# set this to the absolute path of the root directly you are running the
# scripts from.
ROOTDIR=/home/kevina/wordlist/diff/

export PGPORT=5437

export DBNAME=scowl

export PGVER=11
export PGBINDIR=/usr/lib/postgresql/11/bin

export PATH="$PGBINDIR":"$PATH"

export DBROOT="$ROOTDIR"/psqldb

export PGDIR="$DBROOT"/scowl
export PGHOST="$DBROOT"

alias psql=`which psql`
pgctl () {
    pg_ctl -D "$PGDIR" -l "$PGDIR"/log "$@"
}
