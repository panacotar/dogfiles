#!/usr/bin/env bash
# Optional second stage. bootstrap.sh owns common tools, shells and config links.
if [ -n "${ZSH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  cat <<'HELP'
Usage: bash install.sh

Optional post-installation for macOS and Debian/Mint after bootstrap.sh.
Prompts cover Ruby/Go/Python/Node tooling, security tools, DBeaver, Zellij,
applications, and desktop/hardware extras. No shared dotfiles are relinked.
For the first-machine setup or its preview, use bash bootstrap.sh [--dry-run].
Omarchy uses bootstrap.sh and omarchy/install.sh instead.
HELP
  exit 0
fi
[[ $# == 0 ]] || { printf 'Unknown argument: %s\n' "$1" >&2; exit 2; }
[[ $(id -u) != 0 ]] || { echo 'Run as your normal user, not root.' >&2; exit 1; }
exec 3</dev/tty
ask() {
  local answer
  printf '\n%s [y/N] ' "$1"
  IFS= read -r answer <&3
  [[ "$answer" == y || "$answer" == Y ]]
}
root() { sudo -v <&3; sudo "$@"; }
packages() {
  if [[ "$os" == macos ]]; then brew install "$@"; else root apt-get install -y "$@"; fi
}
clone_missing() {
  if [[ -d "$2/.git" ]]; then return; fi
  [[ ! -e "$2" && ! -L "$2" ]] || { printf 'Existing directory needs review: %s\n' "$2" >&2; exit 1; }
  mkdir -p "$(dirname "$2")"
  git clone "$1" "$2"
}

case "$(uname -s)" in
  Darwin) os=macos ;;
  Linux)
    if command -v pacman >/dev/null 2>&1 && { pacman -Q omarchy >/dev/null 2>&1 || [[ -d /usr/share/omarchy || -d "$HOME/.local/share/omarchy" ]]; }; then
      echo 'This post-installer targets macOS/Debian/Mint. On Omarchy, use bootstrap.sh.' >&2
      exit 1
    fi
    ID= ID_LIKE=
    . /etc/os-release
    case " $ID $ID_LIKE " in
      *' debian '*|*' ubuntu '*|*' linuxmint '*) os=debian ;;
      *) echo 'Unsupported distribution.' >&2; exit 1 ;;
    esac ;;
  *) echo 'Unsupported operating system.' >&2; exit 1 ;;
esac
for tool in git curl zsh jq gpg; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing $tool; run bootstrap.sh first." >&2; exit 1; }
done
if [[ "$os" == macos ]]; then
  if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
  command -v brew >/dev/null 2>&1 || { echo 'Run bootstrap.sh to install Homebrew first.' >&2; exit 1; }
else
  root apt-get update
fi

tmp_dir=
trap 'if [[ -n "$tmp_dir" ]]; then rm -rf -- "$tmp_dir"; fi' EXIT
trap 'printf "Post-installation failed at line %s; fix the reported issue and rerun.\n" "$LINENO" >&2' ERR

if ask 'Install Ruby tooling (rbenv and ruby-build)?'; then
  if [[ "$os" == macos ]]; then
    packages rbenv ruby-build libyaml
  else
    packages build-essential tk-dev zlib1g-dev libssl-dev libffi-dev libxml2-dev libxslt1-dev libreadline-dev libyaml-dev libsqlite3-dev
    clone_missing https://github.com/rbenv/rbenv.git "$HOME/.rbenv"
    clone_missing https://github.com/rbenv/ruby-build.git "$HOME/.rbenv/plugins/ruby-build"
  fi
  echo 'Choose the Ruby version for your projects with: rbenv install VERSION'
fi
if ask 'Install Go?'; then
  if [[ "$os" == macos ]]; then packages go; else packages golang-go; fi
fi
if ask 'Install Python tooling (pyenv and pyenv-virtualenv)?'; then
  if [[ "$os" == macos ]]; then
    packages pyenv pyenv-virtualenv
  else
    packages build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncurses-dev xz-utils tk-dev libffi-dev liblzma-dev
    clone_missing https://github.com/pyenv/pyenv.git "$HOME/.pyenv"
    clone_missing https://github.com/pyenv/pyenv-virtualenv.git "$HOME/.pyenv/plugins/pyenv-virtualenv"
  fi
fi
if ask 'Install Node tooling (nvm, without choosing a Node version)?'; then
  if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
    [[ ! -e "$HOME/.nvm" ]] || { echo 'Review the existing incomplete ~/.nvm installation.' >&2; exit 1; }
    version=$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest | jq -er .tag_name)
    [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid nvm release.' >&2; exit 1; }
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles-post.XXXXXX")
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$version/install.sh" -o "$tmp_dir/nvm.sh"
    PROFILE=/dev/null NVM_DIR="$HOME/.nvm" bash "$tmp_dir/nvm.sh"
    rm -rf -- "$tmp_dir"; tmp_dir=
  fi
  echo 'Open a new terminal, then run nvm install --lts (or a project-specific version).'
fi
if ask 'Install security tools?'; then
  if [[ "$os" == macos ]]; then
    packages nmap nikto wpscan
  else
    packages nmap cewl crunch wfuzz seclists hashcat python3-impacket ruby-dev
    root gem install wpscan
    clone_missing https://github.com/sullo/nikto.git "$HOME/code/misc/nikto"
    command -v go >/dev/null 2>&1 || packages golang-go
    go install github.com/OJ/gobuster/v3@latest
  fi
fi
if ask 'Install DBeaver?'; then
  if [[ "$os" == macos ]]; then
    brew install --cask dbeaver-community
  else
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles-post.XXXXXX")
    curl -fsSL https://dbeaver.io/debs/dbeaver.gpg.key -o "$tmp_dir/dbeaver.key"
    gpg --batch --yes --dearmor -o "$tmp_dir/dbeaver.gpg" "$tmp_dir/dbeaver.key"
    root install -m 0644 "$tmp_dir/dbeaver.gpg" /usr/share/keyrings/dbeaver.gpg
    printf 'deb [signed-by=/usr/share/keyrings/dbeaver.gpg] https://dbeaver.io/debs/dbeaver-ce /\n' | root tee /etc/apt/sources.list.d/dbeaver.list >/dev/null
    root apt-get update
    packages dbeaver-ce
    rm -rf -- "$tmp_dir"; tmp_dir=
  fi
fi
if ask 'Install Zellij?'; then
  if [[ "$os" == macos ]]; then packages zellij; else bash "$script_dir/zellij/install_zellij.sh"; fi
  echo 'Zellij uses the config linked by bootstrap.sh under the XDG config directory.'
fi
if [[ "$os" == macos ]]; then
  if ask 'Install development applications and services (VS Code, Alacritty, PostgreSQL 15, libpq, Overmind)?'; then
    packages postgresql@15 libpq overmind
    brew install --cask visual-studio-code alacritty
    brew link --force libpq
  fi
  if ask 'Install the StripMe Finder service?'; then
    mkdir -p "$HOME/Library/Services"
    cp -R "$script_dir/misc/automator-macos/StripMe.workflow" "$HOME/Library/Services/"
  fi
  if ask 'Enable keyboard repeat instead of the accented-character popup?'; then
    defaults write -g ApplePressAndHoldEnabled -bool false
  fi
else
  if ask 'Install desktop/hardware extras (fingerprint support, codecs, VPN, webcam, audio controls)?'; then
    packages fprintd libpam-fprintd libavcodec-extra openvpn cheese pavucontrol python3-pip
  fi
  if ask 'Set GNOME Terminal close-tab to Ctrl+Alt+W?'; then
    dconf write /org/gnome/terminal/legacy/keybindings/close-tab "'<Primary><Alt>w'"
  fi
  if ask 'Enable Firefox XInput2 smooth scrolling?'; then
    printf 'export MOZ_USE_XINPUT2=1\n' | root tee /etc/profile.d/use-xinput2.sh >/dev/null
  fi
  if ask 'Add the legacy external-monitor RGB setting (DP-2) to ~/.xprofile?'; then
    monitor_line='xrandr --output DP-2 --set "Broadcast RGB" "Full"'
    if ! grep -Fxq "$monitor_line" "$HOME/.xprofile" 2>/dev/null; then printf '%s\n' "$monitor_line" >> "$HOME/.xprofile"; fi
  fi
  if ask 'Install Alacritty terminfo?'; then
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles-post.XXXXXX")
    curl -fsSL https://raw.githubusercontent.com/alacritty/alacritty/master/extra/alacritty.info -o "$tmp_dir/alacritty.info"
    tic -xe alacritty,alacritty-direct "$tmp_dir/alacritty.info"
    rm -rf -- "$tmp_dir"; tmp_dir=
  fi
fi
printf '\nPost-installation complete. Open a new terminal for optional runtime integrations.\n'
