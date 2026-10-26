#!/usr/bin/env bash
# Optional second stage. bootstrap.sh owns common tools, shells and config links.
if [ -n "${ZSH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -Eeuo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  cat <<'HELP'
Usage: bash install.sh

Optional post-installation for macOS and Debian/Mint after bootstrap.sh.
Select Ruby/Go/Python/Node tooling, security tools, DBeaver,
applications, and desktop/hardware extras in the initial checkbox menu.
Enter option numbers to toggle choices; press Enter to install the selection.
All choices start unchecked. Use a for all, n for none, or q to cancel.
On macOS, continuing always applies every setting in conf/macos without
confirmation, even if no optional packages are selected. q cancels everything.
No shared dotfiles are relinked.
Each run saves terminal output and errors under logs/install-*/output.log.
Failures print the log path; --help does not create a log.
For the first-machine setup or its preview, use bash bootstrap.sh [--dry-run].
Omarchy uses bootstrap.sh and omarchy/install.sh instead.
HELP
  exit 0
fi
[[ $# == 0 ]] || { printf 'Unknown argument: %s\n' "$1" >&2; exit 2; }

# Run the installer through tee so output stays visible and the parent waits for
# the entire log to flush before exiting. A plain process-substitution logger
# cannot be waited on reliably with macOS's Bash 3.2.
if [[ ${DOGFILES_INSTALL_LOGGED:-} != 1 ]]; then
  run_log_dir=$(umask 077; mkdir -p "$script_dir/logs" &&
    mktemp -d "$script_dir/logs/install-$(date +%Y%m%d-%H%M%S)-XXXXXX") || {
    printf 'Cannot create an installation log under %s/logs.\n' "$script_dir" >&2
    exit 1
  }
  log_file="$run_log_dir/output.log"
  (umask 077; : > "$log_file")
  console_is_tty=false
  if [[ -t 1 ]]; then console_is_tty=true; fi
  set +e
  DOGFILES_INSTALL_LOGGED=1 DOGFILES_INSTALL_LOG="$log_file" \
    DOGFILES_INSTALL_COLOR="$console_is_tty" bash "$script_dir/install.sh" "$@" 2>&1 | tee -a "$log_file"
  run_status=("${PIPESTATUS[@]}")
  if [[ ${run_status[1]} != 0 ]]; then
    printf 'Writing the installation log failed: %s\n' "$log_file" >&2
    if [[ ${run_status[0]} == 0 ]]; then exit "${run_status[1]}"; fi
  fi
  exit "${run_status[0]}"
fi

log_file=${DOGFILES_INSTALL_LOG:?Missing installation log path}
tmp_dir=
failed_line=
record_error() {
  local status=$1 line=$2 command=$3
  if [[ -z "$failed_line" ]]; then
    failed_line=$line
    printf 'Command failed (status %s) at line %s: %s\n' "$status" "$line" "$command" >&2
  fi
}
finish() {
  local status=$1 line=${failed_line:-$2}
  trap - EXIT
  if [[ -n "$tmp_dir" ]]; then rm -rf -- "$tmp_dir" || true; fi
  if [[ "$status" != 0 ]]; then
    printf 'Post-installation failed at line %s; fix the reported issue and rerun. Logged in %s\n' "$line" "$log_file" >&2
  else
    printf 'Logged in %s\n' "$log_file"
  fi
  exit "$status"
}
trap 'record_error "$?" "$LINENO" "$BASH_COMMAND"' ERR
trap 'finish "$?" "$LINENO"' EXIT
printf 'Post-installation started: %s\nLog: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')" "$log_file"

[[ $(id -u) != 0 ]] || { echo 'Run as your normal user, not root.' >&2; exit 1; }
exec 3</dev/tty

# Preserve terminal colors when the logging wrapper sends stdout through tee.
source "$script_dir/scripts/output.sh"
init_output "${DOGFILES_INSTALL_COLOR:-false}"

# A numbered checkbox menu works with macOS's Bash 3.2 and needs no extra tools.
# Collect every choice before running package managers, downloads, or settings.
collect_choices() {
  option_ids=(ruby go python node sec dbeaver)
  option_labels=(
    'Ruby tooling (rbenv and ruby-build)'
    'Go'
    'Python tooling (pyenv and pyenv-virtualenv)'
    'Node tooling (nvm; choose a Node version afterward)'
    'Security tools'
    'DBeaver'
  )
  if [[ "$os" == macos ]]; then
    option_ids+=(dev_apps stripme)
    option_labels+=(
      'Development apps/services (VS Code, Alacritty, PostgreSQL 15, libpq, Overmind)'
      'StripMe Finder service'
    )
  else
    option_ids+=(desktop terminal_key firefox monitor terminfo)
    option_labels+=(
      'Desktop/hardware extras (fingerprint, codecs, VPN, webcam, audio controls)'
      'GNOME Terminal close-tab shortcut: Ctrl+Alt+W'
      'Firefox XInput2 smooth scrolling'
      'Legacy external-monitor RGB setting (DP-2) in ~/.xprofile'
      'Alacritty terminfo'
    )
  fi
  choices=()
  local i input token index mark invalid
  local requested=()
  for ((i=0; i<${#option_ids[@]}; i++)); do choices+=(0); done
  if [[ "$os" == macos ]]; then
    printf '\nAll settings in conf/macos will be applied automatically when you continue.\nUse q to cancel the entire installation.\n'
  fi
  while true; do
    printf '\n%sChoose optional installations and settings:%s\n' "$BOLD" "$NORMAL"
    for ((i=0; i<${#option_ids[@]}; i++)); do
      mark=' '
      if [[ ${choices[$i]} == 1 ]]; then mark=x; fi
      printf '  [%s] %2d. %s\n' "$mark" "$((i+1))" "${option_labels[$i]}"
    done
    printf '\nToggle numbers (e.g. 1 3 6), a=all, n=none, q=quit.\nPress Enter to install the selected items: '
    if ! IFS= read -r input <&3; then
      printf '\nSelection cancelled.\n'
      return 1
    fi
    case "$input" in
      '') return 0 ;;
      q|Q) printf '\nSelection cancelled.\n'; return 1 ;;
      a|A|n|N)
        mark=0
        if [[ "$input" == a || "$input" == A ]]; then mark=1; fi
        for ((i=0; i<${#choices[@]}; i++)); do choices[$i]=$mark; done ;;
      *)
        IFS=$' \t\n' read -r -a requested <<< "${input//,/ }"
        invalid=false
        # Validate the entire line before changing any checkboxes.
        for token in ${requested[@]+"${requested[@]}"}; do
          if [[ ! "$token" =~ ^[0-9]{1,2}$ ]]; then invalid=true; break; fi
          index=$((10#$token - 1))
          if ((index < 0 || index >= ${#choices[@]})); then invalid=true; break; fi
        done
        if "$invalid"; then
          printf 'Choose numbers between 1 and %s, or a, n, q.\n' "${#choices[@]}"
          continue
        fi
        for token in ${requested[@]+"${requested[@]}"}; do
          index=$((10#$token - 1))
          choices[$index]=$((1 - choices[$index]))
        done ;;
    esac
  done
}
selected() {
  local i
  for ((i=0; i<${#option_ids[@]}; i++)); do
    if [[ ${option_ids[$i]} == "$1" ]]; then
      [[ ${choices[$i]} == 1 ]]
      return
    fi
  done
  return 1
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
  trumpet '#####   Installing Mac   #####'
  if command -v brew >/dev/null 2>&1; then eval "$(brew shellenv)"
  elif [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"
  fi
  command -v brew >/dev/null 2>&1 || { echo 'Run bootstrap.sh to install Homebrew first.' >&2; exit 1; }
else
  trumpet '#####   Installing Linux   #####'
fi

if ! collect_choices; then exit 0; fi
selection_count=0
for choice in "${choices[@]}"; do selection_count=$((selection_count + choice)); done
if [[ "$selection_count" == 0 && "$os" != macos ]]; then
  echo 'No options selected. Nothing to install.'
  exit 0
fi
trumpet 'Selection complete. Installing selected options...'
for ((i=0; i<${#option_ids[@]}; i++)); do
  if [[ ${choices[$i]} == 1 ]]; then printf '  - %s\n' "${option_labels[$i]}"; fi
done
if [[ "$os" == macos ]]; then printf '  - All macOS settings in conf/macos\n'; fi

if [[ "$os" == debian ]]; then
  progress_comm 'Updating the local package index...'
  root apt-get update
fi

if selected ruby; then
  trumpet 'Installing Ruby tooling (rbenv and ruby-build)...'
  if [[ "$os" == macos ]]; then
    packages rbenv ruby-build libyaml
  else
    packages build-essential tk-dev zlib1g-dev libssl-dev libffi-dev libxml2-dev libxslt1-dev libreadline-dev libyaml-dev libsqlite3-dev
    clone_missing https://github.com/rbenv/rbenv.git "$HOME/.rbenv"
    clone_missing https://github.com/rbenv/ruby-build.git "$HOME/.rbenv/plugins/ruby-build"
  fi
  echo 'Choose the Ruby version for your projects with: rbenv install VERSION'
fi
if selected go; then
  trumpet 'Installing Go...'
  if [[ "$os" == macos ]]; then packages go; else packages golang-go; fi
fi
if selected python; then
  trumpet 'Installing Python tooling (pyenv and pyenv-virtualenv)...'
  if [[ "$os" == macos ]]; then
    packages pyenv pyenv-virtualenv
  else
    packages build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncurses-dev xz-utils tk-dev libffi-dev liblzma-dev
    clone_missing https://github.com/pyenv/pyenv.git "$HOME/.pyenv"
    clone_missing https://github.com/pyenv/pyenv-virtualenv.git "$HOME/.pyenv/plugins/pyenv-virtualenv"
  fi
fi
if selected node; then
  trumpet 'Installing Node tooling (nvm)...'
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
if selected sec; then
  trumpet 'Installing security tools...'
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
if selected dbeaver; then
  trumpet 'Installing DBeaver...'
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
if [[ "$os" == macos ]]; then
  if selected dev_apps; then
    trumpet 'Installing development applications and services...'
    packages postgresql@15 libpq overmind
    brew install --cask visual-studio-code alacritty
    brew link --force libpq
  fi
  if selected stripme; then
    trumpet 'Installing the StripMe Finder service...'
    mkdir -p "$HOME/Library/Services"
    cp -R "$script_dir/misc/automator-macos/StripMe.workflow" "$HOME/Library/Services/"
  fi
  trumpet 'Applying macOS settings from conf/macos...'
  bash "$script_dir/conf/macos"
else
  if selected desktop; then
    trumpet 'Installing desktop and hardware extras...'
    packages fprintd libpam-fprintd libavcodec-extra openvpn cheese pavucontrol python3-pip
  fi
  if selected terminal_key; then
    trumpet 'Configuring the GNOME Terminal close-tab shortcut...'
    dconf write /org/gnome/terminal/legacy/keybindings/close-tab "'<Primary><Alt>w'"
  fi
  if selected firefox; then
    trumpet 'Enabling Firefox XInput2 smooth scrolling...'
    printf 'export MOZ_USE_XINPUT2=1\n' | root tee /etc/profile.d/use-xinput2.sh >/dev/null
  fi
  if selected monitor; then
    trumpet 'Configuring the legacy external-monitor RGB setting (DP-2)...'
    monitor_line='xrandr --output DP-2 --set "Broadcast RGB" "Full"'
    if ! grep -Fxq "$monitor_line" "$HOME/.xprofile" 2>/dev/null; then printf '%s\n' "$monitor_line" >> "$HOME/.xprofile"; fi
  fi
  if selected terminfo; then
    trumpet 'Installing Alacritty terminfo...'
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles-post.XXXXXX")
    curl -fsSL https://raw.githubusercontent.com/alacritty/alacritty/master/extra/alacritty.info -o "$tmp_dir/alacritty.info"
    tic -xe alacritty,alacritty-direct "$tmp_dir/alacritty.info"
    rm -rf -- "$tmp_dir"; tmp_dir=
  fi
fi
printf '\nPost-installation complete. Open a new terminal for optional runtime integrations.\n'
