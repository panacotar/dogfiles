#!/bin/zsh

echo "#####   Installing Linux   #####"

symlinkFiles=("zshrc" "aliases" "gitconfig" "irbrc" "rspec" "tmux.conf")

echo "Do you want to swap CTRL - CAPS LOCK keys (y/n)"
read key_swap_confim

echo "Do you want to install DBeaver (y/n)"
read dbeaver_confirm

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

if [ $dbeaver_confirm = 'y' ]
then
  trumpet "Install DBeaver..."
  attempt_run sudo  wget -O /usr/share/keyrings/dbeaver.gpg.key https://dbeaver.io/debs/dbeaver.gpg.key
  attempt_run echo "deb [signed-by=/usr/share/keyrings/dbeaver.gpg.key] https://dbeaver.io/debs/dbeaver-ce /" | sudo tee /etc/apt/sources.list.d/dbeaver.list
  attempt_run sudo apt-get update && sudo apt-get install dbeaver-ce
fi

trumpet "Updating the list of available packages + versions..."
attempt_run sudo apt update

trumpet "Upgrading the installed packages..."
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

trumpet "Configuring mozilla smooth scrolling..."
attempt_run echo export MOZ_USE_XINPUT2=1 | sudo tee /etc/profile.d/use-xinput2.sh

trumpet "Installing ngrok..."
attempt_run curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
  | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
attempt_run echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
  | sudo tee /etc/apt/sources.list.d/ngrok.list
attempt_run sudo apt update && sudo apt install ngrok

trumpet "Specifying the Broadcast RGB (for external monitors)...\ ! You might need to change the output from DP-2 to others (run xrandr to list outputs)"
attempt_run echo 'xrandr --output DP-2 --set "Broadcast RGB" "Full"' >> ~/.xprofile

trumpet "Installing nmap..."
attempt_run sudo apt-get install nmap -y

trumpet "Installing wpscan..."
attempt_run sudo apt install ruby-dev -y
attempt_run sudo gem install wpscan

trumpet "Installing nikto (the git version)..."
attempt_run git clone https://github.com/sullo/nikto ~/code/misc/nikto

trumpet "Installing Go..."
progress_comm "Downloading Go tar archive"
attempt_run wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
progress_comm "Remove previous Go installations"
rm -rf /usr/local/go
progress_comm "Extract the tar archive"
attempt_run tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
progress_comm "Remove the tar archive"
rm go${GO_VERSION}.linux-amd64.tar.gz

trumpet "Installing gobuster..."
attempt_run go install github.com/OJ/gobuster/v3@latest

trumpet "Installing seclist..."
attempt_run sudo apt-get install seclists

trumpet "Installing tmux..."
attempt_run sudo apt install tmux -y