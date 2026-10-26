#!/usr/bin/env bash
set -euo pipefail
echo "Type in your first and last name: "
read -r full_name

echo "Type in your email address (the one used for your GitHub account): "
read -r email

git config --global user.email "$email"
git config --global user.name "$full_name"

echo "Configuring global gitignore"
git config --global core.excludesfile "$HOME/.gitignore"

echo "👌 Awesome, all set."
