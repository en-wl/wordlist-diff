#!/usr/bin/env bash
set -euo pipefail

git push diff diff $( for f in $(git tag -l | grep -F diff/); do echo $f:$(basename $f); done )
