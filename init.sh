# create the tmp git repo

set -e

if mountpoint -q git; then sudo umount git; fi
sudo mount -t tmpfs -o size=512M none git
cd git
ln -s ../git-disk/.git

