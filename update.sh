# this will update an already populated git-disk

set -ex

cd git-disk

git fetch src
git checkout master
git reset --hard src/master
git clean -xfd

git fetch diff
git branch -f diff diff/diff

cd ..

sh init.sh

cd git
perl ../doit.pl

echo 'now do: cd git; sh ../push.sh'
