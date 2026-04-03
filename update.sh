#!/usr/bin/env bash
set -euo pipefail

# This will update an already populated git-disk

: ${SCOWL_BRANCH:=v2}
export SCOWL_BRANCH
: ${DIFF_BRANCH:=diff}
export DIFF_BRANCH
ROOTDIR="$PWD"
cd git-disk

git reset --hard
git clean -xfd
git fetch src
git checkout "$SCOWL_BRANCH"
git reset --hard src/"$SCOWL_BRANCH"

#git fetch diff
#git branch -f diff diff/diff

cd ..

if ! mountpoint -q git; then
	./init.sh
fi

cd git
PATH="$ROOTDIR/bin:$PATH" ../doit.pl

echo 'now do: cd git; ../push.sh'
