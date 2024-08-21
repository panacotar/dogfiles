#!/bin/zsh

echo "#####   Installing Mac   #####"

symlinkFiles=("zshrc" "aliases" "gitconfig" "gitignore" "macos" "pryrc" "tmux.conf";)

trumpet "Installing tldr..."
attempt_run brew install tldr

trumpet "Updating tldr..."
attempt_run tldr -u

trumpet "Installing nmap..."
attempt_run brew install nmap

trumpet "Installing wpscan..."
attempt_run brew install wpscanteam/tap/wpscan
attempt_run brew install wpscanteam/tap/wpscan --HEAD

trumpet "Installing nikto..."
attempt_run brew install nikto

trumpet "Installing lazygit..."
attempt_run brew install lazygit

echo "After installing iTerm2, import the 'Dario_iterm2_profile.json' into it."
