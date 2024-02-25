#!/bin/zsh

echo "Installing Linux"

symlinkFiles=("zshrc" "aliases" "gitconfig" "irbrc" "rspec")

echo "Do you want to swap CTRL - CAPS LOCK keys (y/n)"
read key_swap_confim

if [ $key_swap_confim = 'y' ]
then
  echo "Swapping keys CTRL - CAPS LOCK..."
  # Add command to zshrc (will always be executed when zshrc is sourced)
  # The option might be `caps:nocaps` in some cases
  echo "\n# Swaps keys ctrl-caps" >> zshrc
  echo "eval 'setxkbmap -option ctrl:swapcaps'" >> zshrc

  # Alternative using xmodmap config file
  # backup "$HOME/.xmodmap"
  # symlink "$PWD/xmodmap" "$HOME/.xmodmap"
  # echo "eval 'xmodmap ~/.xmodmap'" >> zshrc

  # Alternative using gnome-tweaks
  # gsettings set org.gnome.desktop.input-sources xkb-options "['ctrl:nocaps']"
fi

trumpet "Update the list of available packages + versions..."
attempt_run sudo apt update

trumpet "Upgrade the installed packages..."
attempt_run sudo apt upgrade

trumpet "Installing fingerprint scanner..."
attempt_run sudo apt install fprintd libpam-fprintd -y

trumpet "Installing sqlite3..."
attempt_run sudo apt-get install -y sqlite3 libsqlite3-dev

trumpet "Installing xclip (clipboard copy) + aliases with pbcopy..."
attempt_run sudo apt-get install xclip

trumpet "Installing libavcodec-extra"
attempt_run sudo apt install libavcodec-extra -y

trumpet "Installing cewl, crunch, wfuzz"
attempt_run sudo apt-get install cewl crunch wfuzz -y

trumpet "Installing tldr..."
attempt_run sudo apt-get install tldr -y

trumpet "Updating tldr..."
attempt_run tldr -u

trumpet "Config mozilla smooth scrolling"
attempt_run echo export MOZ_USE_XINPUT2=1 | sudo tee /etc/profile.d/use-xinput2.sh

trumpet "Install ngrok"
attempt_run curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | \
  sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null && \
  echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | \
  sudo tee /etc/apt/sources.list.d/ngrok.list && \
  sudo apt update && sudo apt install ngrok
