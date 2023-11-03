#!/bin/zsh

echo "Installing Mac"

symlinkFiles=("zshrc" "aliases" "gitconfig" "gitignore" "macos" "pryrc";)

trumpet "Installing tldr..."
attempt_run brew install tldr