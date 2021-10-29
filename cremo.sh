#!/bin/bash

# sets a new remote origin URL
function cremo() {
  if [ $# -eq 0 ]
    then
      echo "No arguments supplied"
      exit 1
  fi
  echo 'Changing remote origin...'
  echo ' '
  OLD=$(git remote get-url origin)
  (git remote set-url origin $1)
  echo "origin changed from:  $OLD"
  echo '                 ---                        '
  echo "origin changed   to:  $(git remote get-url origin)"
}
