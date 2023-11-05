#!/bin/zsh

bold=$(tput bold)
normal=$(tput sgr0)

# Define a function which rename a `target` file to `target.backup` if the file
# exists and if it's a 'real' file, ie not a symlink
backup() {
  target=$1
  if [ -e "$target" ]; then           # Does the config file already exist?
    if [ ! -L "$target" ]; then       # as a pure file?
      mv "$target" "$target.backup"   # Then backup it
      echo "-----> Moved your old $target config file to $target.backup"
    fi
  fi
}

symlink() {
  file=$1
  link=$2
  if [ ! -e "$link" ]; then
    echo "-----> Symlinking your new $link"
    ln -s $file $link
  fi
}

attempt_run() {
  $* || (echo "\nfailed" 1>&2 && exit 1)
}

trumpet() {
  echo "\n*** $1 ***\n"
}

# Detect the OS + exit if something other than Linux/(Darwin) MacOS
detect_os() {
  unameOut="$(uname -s)"
  case "${unameOut}" in
      Linux*)     os=linux;;
      Darwin*)    os=mac;;
      *)          echo "\n> install.sh not supporting OS: ${unameOut}\nExiting..." && exit 0
  esac
}
detect_os

echo "Are you sure you want to install ${bold}${(C)os}${normal} configs? (y/n)"
read confirm

if [ $confirm != 'y' ]
then
  echo "Exiting..."
  exit 0
fi

# Instal OS specific stuff
if [ $os = 'linux' ]; then
  source ./_install_linux.sh
elif [ $os = 'mac' ]; then
  source ./_install_mac.sh
else
  echo "Exiting..."
  exit 0
fi

# TODO
# - Add section with initializing the ssh keys (manually)

# Backup the target file located at `~/.$name` and symlink `$name` to `~/.$name`
# symlinkFiles different files based on the OS
for name in ${symlinkFiles[@]}; do
  if [ ! -d "$name" ]; then
    target="$HOME/.$name"
    backup $target
    echo "-----> Symlinking your new $target"
    symlink $PWD/$name $target
  fi
done

REGULAR="\\033[0;39m"
YELLOW="\\033[1;33m"
GREEN="\\033[1;32m"

# Install zsh-syntax-highlighting plugin
CURRENT_DIR=`pwd`
ZSH_PLUGINS_DIR="$HOME/.oh-my-zsh/custom/plugins"
mkdir -p "$ZSH_PLUGINS_DIR" && cd "$ZSH_PLUGINS_DIR"
if [ ! -d "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting" ]; then
  echo "-----> Installing zsh plugin 'zsh-syntax-highlighting'..."
  git clone https://github.com/zsh-users/zsh-autosuggestions
  git clone https://github.com/zsh-users/zsh-syntax-highlighting
fi
cd "$CURRENT_DIR"

setopt nocasematch
if [[ ! `uname` =~ "Darwin" ]]; then
  CODE_PATH=~/Library/Application\ Support/Code/User
else
  # Else, it's a Linux
  CODE_PATH=~/.config/Code/User

  # If no folder, then it's WSL
  if [ ! -e $CODE_PATH ]; then
    CODE_PATH=~/.vscode-server/data/Machine
  fi
fi

zsh ~/.zshrc

echo "👌  Carry on with git setup!"
