#!/bin/bash

# Adds a custom variable to zshrc (to be accessible globally)
function lay() {
   if [ $# -lt 2 ]; then
       echo -e "You need to specify two arguments.\n\nusage: lay <VARIABLE_NAME> <VARIABLE_VALUE>"
       return 1
   fi
   echo "export $1=$2" | tee -a /tmp/shared_vars.sh
}

