. ./psqldb-env.sh

set -e

# create the psql database

if findmnt psqldb
then
    pgctl stop
    sudo umount psqldb
fi

sudo mount -t tmpfs -o size=1G none psqldb

pgctl init -D "$PGDIR"
cat <<EOF >> "$PGDIR"/postgresql.auto.conf
port = $PGPORT
unix_socket_directories = '$PGHOST'
wal_level = minimal
fsync = off
full_page_writes = off
max_wal_senders = 0
seq_page_cost = 1.0                     # measured on an arbitrary scale
random_page_cost = 1.1                  # same scale as above
work_mem = 256MB
max_wal_size = 512MB
EOF
pgctl start

createdb $DBNAME
psql scowl -f comp/util-fun.sql
psql scowl -f comp/comp-init.sql

