#!/bin/zsh

echo "Installing Mac"

symlinkFiles=("zshrc" "aliases" "gitconfig" "gitignore" "macos" "pryrc";)

trumpet "Installing tldr..."
attempt_run brew install tldr

trumpet "Updating tldr..."
attempt_run tldr -u

echo "After installing iTerm2, import the 'Dario_iterm2_profile.json' into it."