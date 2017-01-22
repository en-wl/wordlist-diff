# setup the git-disk repo

set -e

git init git-disk
cd git-disk
#git remote add src git@github.com:en-wl/wordlist.gi
git remote add src /home/kevina/wordlist/git
git remote add diff git@github.com:en-wl/wordlist-diff.git
git fetch src
git fetch diff diff
git branch master src/master
git branch diff diff/diff
git checkout master
