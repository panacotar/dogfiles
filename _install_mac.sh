#!/bin/zsh

echo "##############################"
echo "#####   Installing Mac   #####"

symlinkFiles=("zshrc" "aliases" "custom_commands.sh" "gitconfig" "gitignore" "macos" "pryrc" "tmux.conf";)

trumpet "Installing tldr..."
attempt_run brew install tldr

trumpet "Updating tldr..."
attempt_run tldr -u

trumpet "Installing lazygit..."
attempt_run brew install lazygit

###################
# Sec
####################

trumpet "Installing nmap..."
attempt_run brew install nmap

trumpet "Installing wpscan..."
attempt_run brew install wpscanteam/tap/wpscan
attempt_run brew install wpscanteam/tap/wpscan --HEAD

trumpet "Installing nikto..."
attempt_run brew install nikto


trumpet "After installing iTerm2, import the 'Dario_iterm2_profile.json' into it."
