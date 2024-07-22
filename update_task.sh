#!/bin/bash

# Automatic system update script (testing)
# To allow executing this script:
# chmod u+x update.sh

# Update
sudo apt update
sudo apt upgrade

# Log Update
printf "[`date -u +%Y-%m-%dT%H:%M:%S%Z`] System updated\n\n" >> ~/sys_update_log.txt

