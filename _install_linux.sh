#!/bin/zsh


symlinkFiles=("zshrc" "aliases" "gitconfig" "irbrc" "rspec")

echo "Installing Linux"

echo "Do you want to swap CTRL - CAPS LOCK keys (y/n)"
read key_swap_confim

if [ $key_swap_confim = 'y' ]
then
  echo "Swapping keys CTRL - CAPS LOCK..."
  # Add command to zshrc (will always be executed when zshrc is sourced)
  # The option might be `caps:swapcaps` in some cases
  echo "\n# Swaps keys ctrl-caps" >> zshrc
  echo "setxkbmap -option caps:nocaps" >> zshrc

  # Alternative using gnome-tweaks
  # gsettings set org.gnome.desktop.input-sources xkb-options "['ctrl:nocaps']"
fi

trumpet "Installing sqlite3..."
attempt_run sudo apt-get install sqlite3 libsqlite3-dev

trumpet "Installing xclip (clipboard copy)..."
attempt_run sudo apt-get install xclip