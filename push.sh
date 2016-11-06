git push diff diff \
  $( for f in `git tag -l | fgrep diff/`; do echo $f:`basename $f`; done )     
