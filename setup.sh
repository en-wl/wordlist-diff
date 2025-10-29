# setup the git-disk repo

set -e

git init git-disk
cd git-disk
git remote add src git@github.com:en-wl/wordlist.git
#git remote add src /home/kevina/wordlist/v2-pub
git remote add diff git@github.com:en-wl/wordlist-diff.git
git fetch src v1
git fetch src
git fetch diff diff
git branch v2 src/v2
git branch diff diff/diff
git checkout v2
git replace --graft 0ff67eb0ba18648fbf0a55b69962038401d5074c src/v1
