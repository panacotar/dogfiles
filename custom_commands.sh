#!/bin/bash

# Adds a custom variable to zshrc (to be accessible globally)
function lay() {
   if [ $# -lt 2 ]; then
       echo -e "You need to specify two arguments.\n\nusage: lay <VARIABLE_NAME> <VARIABLE_VALUE>"
       return 1
   fi
   echo "export $1=$2" | tee -a ~/.zshenv && exec zsh
}

# # Change REMote Origin - cremo.sh wow!
# # When run inside a local git repository, it sets a new remote origin URL
# function cremo() {
#   if [ $# -eq 0 ]
#     then
#       echo "No arguments supplied"
#       exit 1
#   fi
#   echo 'Changing remote origin...'
#   echo ' '
  
#   # Get the old origin
#   OLD=$(git remote get-url origin)
  
#   # Set the new origin
#   (git remote set-url origin $1)

#   # Print info
#   echo "origin changed from:  $OLD"
#   echo '                 ---                        '
#   echo "origin changed   to:  $(git remote get-url origin)"
# }
