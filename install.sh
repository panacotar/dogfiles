
bold=$(tput bold)
normal=$(tput sgr0)

backup() {
  target=$1
  if [ -e "$target" ]; then           # Does the config file already exist?
    if [ ! -L "$target" ]; then       # as a pure file?
      mv "$target" "$target.backup"   # Then backup it
      echo "-----> Moved your old $target config file to $target.backup"
    fi
  fi
}

echo "Are you sure you want to install ${bold}Linux/Win${normal} configs? (y/n)"
read confirm

if [ $confirm != 'y' ]
then
  echo "Exiting..."
  exit 0
fi

#!/bin/zsh
for name in *; do
  if [ ! -d "$name" ]; then
    target="$HOME/.$name"
    if [[ ! "$name" =~ '\.sh$' ]] && [ "$name" != 'README.md' ] && [[ ! "$name" =~ '\.sublime-settings$' ]]; then
      backup $target

      if [ ! -e "$target" ]; then
        echo "-----> Symlinking your new $target"
        ln -s "$PWD/$name" "$target"
      fi
    fi
  fi
done

REGULAR="\\033[0;39m"
YELLOW="\\033[1;33m"
GREEN="\\033[1;32m"

# zsh plugins
CURRENT_DIR=`pwd`
ZSH_PLUGINS_DIR="$HOME/.oh-my-zsh/custom/plugins"
mkdir -p "$ZSH_PLUGINS_DIR" && cd "$ZSH_PLUGINS_DIR"
if [ ! -d "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting" ]; then
  echo "-----> Installing zsh plugin 'zsh-syntax-highlighting'..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git
  git clone https://github.com/zsh-users/zsh-autosuggestions.git
fi
cd "$CURRENT_DIR"

setopt nocasematch
if [[ ! `uname` =~ "darwin" ]]; then
  echo 'export BUNDLER_EDITOR="subl $@ >/dev/null 2>&1 -a"' >> zshrc
  CODE_PATH=~/Library/Application\ Support/Code/User
else
  # Else, it's a Linux
  bundler_editor="code -w"
  echo "export BUNDLER_EDITOR=\"${bundler_editor}\"" >> zshrc
  CODE_PATH=~/.config/Code/User

  # If no folder, then it's WSL
  if [ ! -e $CODE_PATH ]; then
    CODE_PATH=~/.vscode-server/data/Machine
  fi
fi

fi

zsh ~/.zshrc

echo "👌  Carry on with git setup!"
