#!/bin/zsh

# Inspired by:
# https://github.com/pavkam

BOLD=$(tput bold)
NORMAL=$(tput sgr0)
# Colors .
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)

LOG_FILE=~/.dogfile.log

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

# Create a symlink
# Usage: $ symlink original target_destination
symlink() {
  file=$1
  link=$2
  if [ ! -e "$link" ]; then
    echo "-----> Symlinking your new $link"
    ln -s $file $link
  fi
}

function log() {
  TIME=$(date '+%d/%m/%Y %H:%M:%S')
  echo "[$TIME] $1" | sed -r "s/\\x1B\\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g" >>$LOG_FILE
}

function log_echo() {
  log "$1"
  echo "$1"
}

function err() {
  log_echo "${RED}Error: $1"
  echo "Check '$LOG_FILE' for details."
  exit 1
}

attempt_run() {
  $* || (echo "\nfailed" 1>&2 && exit 1)
}

# Run command with output redirected to log file
function run() {
  "$@" 1>>"$LOG_FILE" 2>>"$LOG_FILE"
}

trumpet() {
  echo "${GREEN}\n#################################\n $1 \n#################################\n${NORMAL}"
}

function is_package_installed() {
  [ -z "$2" ] && err "Expected two arguments to function."
  run $1 "$2"
}

function check_and_collect_packages() {
  local check_command=$1
  shift
  local packages_to_install=""

  for package in "$@"; do
    if ! is_package_installed "$check_command" "$package"; then
      packages_to_install="${packages_to_install:+$packages_to_install }$package"
    fi
  done

  echo "$packages_to_install"
}

function install_packages() {
  if [[ -z "$1" || -z "$2" ]]; then
    echo "Expected two arguments to function."
    err "$0 expects two arguments: cmd string + package list string."
    return 1
  fi

  # In ZSH, $=VAR is doing word splitting => array
  local -a CMD=($=1)
  local -a PACKAGES=($=2)

  trumpet "Installing packages [${PACKAGES[*]}] with '${CMD[*]}'..."

  if ! "$CMD[@]" "$PACKAGES[@]" 1>>$LOG_FILE 2>>$LOG_FILE; then
    err "Failed to install one or more packages from the list ['$2']."
  fi
}

progress_comm() {
  echo "\n\n----->$1 \n"
}

# Detect the OS + exit if something other than Linux/(Darwin) MacOS
detect_os() {
  UNAME_OUT="$(uname -s)"
  case "${UNAME_OUT}" in
      Linux*)     OS=linux;;
      Darwin*)    OS=mac;;
      *)          echo "\n> install.sh not supporting OS: ${UNAME_OUT}\nExiting..." && exit 0
  esac
}
detect_os

install_rbenv_linux() {
  if command -v rbenv&>/dev/null; then
    trumpet "Already installed: rbenv"
    return 0
  fi
  trumpet "Installing rbenv..."
  rvm implode && sudo rm -rf ~/.rvm
  # If you got "zsh: command not found: rvm", carry on.
  # It means `rvm` is not on your computer, that's what we want!
  rm -rf ~/.rbenv

  sudo apt install -y build-essential tklib zlib1g-dev libssl-dev libffi-dev libxml2 libxml2-dev libxslt1-dev libreadline-dev libyaml-dev

  git clone https://github.com/rbenv/rbenv.git ~/.rbenv

  git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
}

install_lazygit_linux() {
  if command -v lazygit &>/dev/null; then
    trumpet "Already installed: lazygit"
    return 0
  fi

  trumpet "Installing lazygit..."
  LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
  attempt_run curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
  tar xf lazygit.tar.gz lazygit
  attempt_run sudo install lazygit /usr/local/bin
  rm lazygit.tar.gz lazygit 
}


install_go_linux() {
  # Prevent installing it if `which go` returns a string
  if command -v go &>/dev/null; then
    trumpet "Already installed: Golang"
    return 0
  fi
  trumpet "Installing Golang..."
  sudo apt autoremove --purge '^golang-1.22*' -y
  sudo apt install golang-1.22 golang-1.22-go golang-1.22-src golang-1.22-doc -y
}

echo "Proceed with installing ${BOLD}${(C)OS}${NORMAL} configs? (y/n)"
read confirm

if [ $confirm != 'y' ]
then
  echo "Exiting..."
  exit 0
fi

if [ $OS = 'linux' ]; then
  echo "${GREEN}################################"
  echo "${GREEN}#####   Installing Linux   #####${NORMAL}"

  SYMLINK_FILES=(zshrc aliases custom_commands.sh gitconfig irbrc rspec tmux.conf vimrc)

  echo "\nDo you want to install ${BOLD}DBeaver${NORMAL}? (y/n)"
  read dbeaver_confirm

  echo "\nDo you want to install ${BOLD}Zellij${NORMAL}? (y/n)"
  read zellij_confirm

  echo "\nDo you want to install ${BOLD}sec related packages${NORMAL}? (y/n)"
  read install_sec

  # Change close-tab keybinding in the terminal
  dconf write /org/gnome/terminal/legacy/keybindings/close-tab "'<Primary><Alt>w'"

  if [ $dbeaver_confirm = 'y' ]
  then
    trumpet "Install DBeaver..."
    attempt_run sudo  wget -O /usr/share/keyrings/dbeaver.gpg.key https://dbeaver.io/debs/dbeaver.gpg.key
    attempt_run echo "deb [signed-by=/usr/share/keyrings/dbeaver.gpg.key] https://dbeaver.io/debs/dbeaver-ce /" | sudo tee /etc/apt/sources.list.d/dbeaver.list
    attempt_run sudo apt-get update && sudo apt-get install dbeaver-ce
  fi

  install_go_linux

  trumpet "Updating the local package index..."
  attempt_run sudo apt update

  trumpet "Upgrading the installed packages..."
  attempt_run sudo apt upgrade -y

  PACKS=(
    fprintd libpam-fprintd sqlite3 libsqlite3-dev pkg-config xclip 
    libavcodec-extra openvpn exiftool tldr tmux gpg tig tree htop
    cheese pavucontrol python3-pip
  )


  if [ $install_sec = 'y' ]
  then
    SEC_PACKS=(
      nmap cewl crunch wfuzz wpscan seclists hashcat python3-impacket
    )

    PACKS+=( "${SEC_PACKS[@]}" )

    trumpet "Installing wpscan..."
    attempt_run sudo apt install ruby-dev -y
    attempt_run sudo gem install wpscan

    trumpet "Installing nikto (the git version)..."
    attempt_run git clone https://github.com/sullo/nikto ~/code/misc/nikto

    trumpet "Installing gobuster..."
    attempt_run go install github.com/OJ/gobuster/v3@latest
  fi

  TO_INSTALL=$(check_and_collect_packages "dpkg -s" "${PACKS[@]}")

  if [ "$TO_INSTALL" != "" ]; then
    install_packages "apt install -y" "$TO_INSTALL"
  fi

  trumpet "Updating tldr..."
  attempt_run tldr -u

  trumpet "Configuring mozilla smooth scrolling..."
  attempt_run echo export MOZ_USE_XINPUT2=1 | sudo tee /etc/profile.d/use-xinput2.sh

  trumpet "Specifying the Broadcast RGB (for external monitors)...\ ! You might need to change the output from DP-2 to others (run xrandr to list outputs)"
  attempt_run echo 'xrandr --output DP-2 --set "Broadcast RGB" "Full"' >> ~/.xprofile

  if [ $zellij_confirm = 'y' ]
  then
    source $PWD/zellij/install_zellij.sh
    mkdir -p $HOME/.config/zellij-me
    symlink $PWD/zellij/config.kdl $HOME/.config/zellij-me/config.kdl
  fi

  install_lazygit_linux
  install_rbenv_linux

elif [ $OS = 'mac' ]; then
  echo "##############################"
  echo "#####   Installing Mac   #####"

  SYMLINK_FILES=(zshrc aliases custom_commands.sh gitconfig gitignore macos pryrc tmux.conf)

  PACKS=(
    tldr lazygit sqlite postgresql@15 libpq tmux gpg tig tree
  )
  
  ###################
  # Sec
  ####################
  echo "\nDo you want to install ${BOLD}sec related packages${NORMAL}? (y/n)"
  read install_sec

  if [ $install_sec = 'y' ]
  then
    SEC_PACKS=(
      nmap seclists nikto wpscan
    )

    PACKS+=( "${SEC_PACKS[@]}" )
  fi

  trumpet "Installing rbenv"
  rvm implode && sudo rm -rf ~/.rvm
  sudo rm -rf $HOME/.rbenv /usr/local/rbenv /opt/rbenv /usr/local/opt/rbenv
  brew uninstall --force rbenv ruby-build
  brew install rbenv libyaml

  TO_INSTALL=$(check_and_collect_packages "brew list" "${PACKS[@]}")

  if [ "$TO_INSTALL" != "" ]; then
    install_packages "brew install" "$TO_INSTALL"
  fi

  # Brew cask packages
  trumpet "Checking brew cask packages..."
  PACKS=(
    visual-studio-code alacritty
  )

  TO_INSTALL=$(check_and_collect_packages "brew list" "${PACKS[@]}")

  if [ "$TO_INSTALL" != "" ]; then
    install_packages "brew install --cask" "$TO_INSTALL"
  fi

  trumpet "Trust Alacritty"
  attempt_run xattr -dr com.apple.quarantine "/Applications/Alacritty.app"
  symlink $PWD/alacritty.toml $HOME/.config/alacritty/alacritty.toml

  trumpet "Link brew libpq"
  attempt_run brew link --force libpq

  trumpet "Updating tldr..."
  attempt_run tldr -u

  trumpet "If installing iTerm2, import the 'Dario_iterm2_profile.json' into it. Or use Alacritty as an alternative"

else
  echo "Exiting..."
  exit 0
fi

# Backup the target file located at `~/.$name` and symlink `$name` to `~/.$name`
# SYMLINK_FILES different files based on the OS
for name in ${SYMLINK_FILES[@]}; do
  if [ ! -d "$name" ]; then
    target="$HOME/.$name"
    backup $target
    symlink $PWD/$name $target
  fi
done

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

: '
  To install packages (common):
code
calibre
'
