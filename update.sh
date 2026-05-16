#!/bin/sh

# this will update an already populated git-disk

set -ex

: ${SCOWL_BRANCH:=v2}
export SCOWL_BRANCH
: ${DIFF_BRANCH:=diff}
export DIFF_BRANCH
ROOTDIR="$PWD"
export SCOWL_CACHE

cd git-disk

git reset --hard
git clean -xfd
git fetch src
git checkout "$SCOWL_BRANCH"
git reset --hard src/"$SCOWL_BRANCH"

#git fetch diff
#git branch -f diff diff/diff

cd ..

if ! mountpoint -q git; then sh init.sh; fi

cd git
PATH="$ROOTDIR/bin:$PATH" perl ../doit.pl

echo 'now do: cd git; sh ../push.sh'
