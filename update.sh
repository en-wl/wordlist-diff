# this will update an already populated git-disk

set -ex

cd git-disk

git fetch src
git checkout v2
git reset --hard src/v2
git clean -xfd

#git fetch diff
#git branch -f diff diff/diff

cd ..

if ! mountpoint -q git; then sh init.sh; fi

cd git
perl ../doit.pl

echo 'now do: cd git; sh ../push.sh'
