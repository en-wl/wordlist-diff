# create the tmp git repo

set -e

mkdir -p git
sudo mount -t tmpfs -o size=512M none git
cd git
ln -s ../git-disk/.git

