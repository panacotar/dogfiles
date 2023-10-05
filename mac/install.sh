#!/bin/zsh

bold=$(tput bold)
normal=$(tput sgr0)

symlink() {
  file=$1
  link=$2
  if [ ! -e "$link" ]; then
    echo "-----> Symlinking your new $link"
    ln -s $file $link
  fi
}

echo "Are you sure you want to install ${bold}MAC${normal} configs? (y/n)"
read confirm

if [ $confirm != 'y' ]
then
  echo "Exiting..."
  exit 0
fi


for name in aliases gitconfig gitignore zshrc pryrc; do
  if [ ! -d "$name" ]; then
    echo $name
    target="$HOME/.$name"
    echo 'Target: ' + $target
    symlink $PWD/$name $target
  fi
done