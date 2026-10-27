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
Enter numbers to toggle choices, a to select all, then an empty Enter to install.
Use n to clear all choices and continue immediately, or q to cancel.
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
source "$script_dir/scripts/sources.sh"

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
  local i input= token index mark invalid menu= row selected_numbers error=
  local can_redraw=false full_menu=true columns lines rows length clear_to_end=
  # The logger pipes stdout through tee; keep cursor controls in that same stream.
  if [[ ${DOGFILES_INSTALL_COLOR:-false} == true && ${TERM:-dumb} != dumb ]] &&
    command -v tput >/dev/null 2>&1; then
    clear_to_end=$(tput ed 2>/dev/null || true)
    if [[ -n "$clear_to_end" ]] && tput cuu 1 >/dev/null 2>&1; then can_redraw=true; fi
  fi
  local requested=()
  for ((i=0; i<${#option_ids[@]}; i++)); do choices+=(0); done
  if [[ "$os" == macos ]]; then
    printf '\nAll settings in conf/macos will be applied automatically when you continue.\nUse q to cancel the entire installation.\n'
  fi
  while true; do
    if [[ -n "$menu" ]]; then
      columns=; lines=
      if "$can_redraw"; then
        read -r lines columns < <(stty size <&3 2>/dev/null) || true
      fi
      if "$can_redraw" && [[ "$columns" =~ ^[1-9][0-9]*$ && "$lines" =~ ^[1-9][0-9]*$ ]]; then
        # Include wrapped rows and the input echoed by the terminal.
        rows=0
        while IFS= read -r row; do
          length=${#row}
          rows=$((rows + (length + columns - 1) / columns))
          if [[ "$length" == 0 ]]; then rows=$((rows + 1)); fi
        done <<< "$menu$input"
        if ((rows < lines)); then
          printf '\r%s%s' "$(tput cuu "$rows")" "$clear_to_end"
        else
          full_menu=false
        fi
      else
        full_menu=false
      fi
    fi
    menu=$'\n'
    if "$full_menu"; then menu+=$'Choose optional installations and settings:\n'; fi
    selected_numbers=
    for ((i=0; i<${#option_ids[@]}; i++)); do
      mark=' '
      if [[ ${choices[$i]} == 1 ]]; then
        mark=x
        selected_numbers+="${selected_numbers:+, }$((i+1))"
      fi
      if "$full_menu"; then
        printf -v row '  [%s] %2d. %s' "$mark" "$((i+1))" "${option_labels[$i]}"
        menu+="$row"$'\n'
      fi
    done
    if [[ -n "$selected_numbers" ]]; then
      menu+="Selected options: $selected_numbers."$'\n'
    else
      menu+=$'No optional items selected.\n'
    fi
    if [[ -n "$error" ]]; then menu+="$error"$'\n'; fi
    menu+=$'\nToggle numbers (e.g. 1 3 6), a=all, n=none and continue, q=quit.\nPress Enter to install the selected items: '
    printf '%s' "$menu"
    error=
    if ! IFS= read -r input <&3; then
      printf '\nSelection cancelled.\n'
      return 1
    fi
    case "$input" in
      '') return 0 ;;
      n|N)
        for ((i=0; i<${#choices[@]}; i++)); do choices[$i]=0; done
        printf '%sNo optional items selected. Continuing...%s\n' "$BOLD" "$NORMAL"
        return 0 ;;
      q|Q) printf '\nSelection cancelled.\n'; return 1 ;;
      a|A)
        for ((i=0; i<${#choices[@]}; i++)); do choices[$i]=1; done ;;
      *)
        IFS=$' \t\n' read -r -a requested <<< "${input//,/ }"
        invalid=false
        if [[ ${#requested[@]} == 0 ]]; then invalid=true; fi
        for token in ${requested[@]+"${requested[@]}"}; do
          if [[ ! "$token" =~ ^[0-9]{1,2}$ ]]; then invalid=true; break; fi
          index=$((10#$token - 1))
          if ((index < 0 || index >= ${#choices[@]})); then invalid=true; break; fi
        done
        if "$invalid"; then
          error="Choose numbers between 1 and ${#choices[@]}, or a, n, q."
          continue
        fi
        for token in "${requested[@]}"; do
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

install_debian_ruby_tooling() {
  if [[ ${ruby_tooling_ready:-false} == true ]]; then return; fi
  packages build-essential tk-dev tklib zlib1g-dev libssl-dev libffi-dev libxml2-dev libxslt1-dev libreadline-dev libyaml-dev libsqlite3-dev
  clone_pinned https://github.com/rbenv/rbenv.git "$HOME/.rbenv" "$RBENV_REVISION"
  clone_pinned https://github.com/rbenv/ruby-build.git "$HOME/.rbenv/plugins/ruby-build" "$RUBY_BUILD_REVISION"
  ruby_tooling_ready=true
}

if selected ruby; then
  trumpet 'Installing Ruby tooling (rbenv and ruby-build)...'
  if [[ "$os" == macos ]]; then
    packages rbenv ruby-build libyaml
  else
    install_debian_ruby_tooling
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
    clone_pinned https://github.com/pyenv/pyenv.git "$HOME/.pyenv" "$PYENV_REVISION"
    clone_pinned https://github.com/pyenv/pyenv-virtualenv.git "$HOME/.pyenv/plugins/pyenv-virtualenv" "$PYENV_VIRTUALENV_REVISION"
  fi
fi
if selected node; then
  trumpet 'Installing Node tooling (nvm)...'
  if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
    [[ ! -e "$HOME/.nvm" ]] || { echo 'Review the existing incomplete ~/.nvm installation.' >&2; exit 1; }
    # nvm works directly from its checkout; no moving installer or second fetch.
    clone_pinned https://github.com/nvm-sh/nvm.git "$HOME/.nvm" "$NVM_REVISION"
  elif [[ -d "$HOME/.nvm/.git" ]]; then
    check_existing_revision "$HOME/.nvm" "$NVM_REVISION"
  fi
  echo 'Open a new terminal, then run nvm install --lts (or a project-specific version).'
fi
if selected sec; then
  trumpet 'Installing security tools...'
  if [[ "$os" == macos ]]; then
    packages nmap nikto wpscan
  else
    packages nmap cewl crunch wfuzz hashcat python3-impacket
    clone_pinned https://github.com/danielmiessler/SecLists.git "$HOME/code/misc/SecLists" "$SECLISTS_REVISION"
    install_debian_ruby_tooling
    # Select this runtime explicitly; sudo would use the older system Ruby.
    # Keep gems isolated from inherited GEM_HOME/GEM_PATH and other Ruby versions.
    rbenv_bin="$HOME/.rbenv/bin/rbenv"
    env -u GEM_HOME -u GEM_PATH RBENV_ROOT="$HOME/.rbenv" RBENV_VERSION="$WPSCAN_RUBY_VERSION" \
      "$rbenv_bin" install -s "$WPSCAN_RUBY_VERSION"
    env -u GEM_HOME -u GEM_PATH RBENV_ROOT="$HOME/.rbenv" RBENV_VERSION="$WPSCAN_RUBY_VERSION" \
      "$rbenv_bin" exec gem install wpscan --version "$WPSCAN_VERSION" --no-document
    # A dedicated launcher also works when the user's project selects another Ruby.
    mkdir -p "$HOME/.local/bin"
    if [[ -e "$HOME/.local/bin/wpscan" || -L "$HOME/.local/bin/wpscan" ]]; then
      mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/dogfiles/backups"
      wpscan_backup=$(mktemp -d "${XDG_STATE_HOME:-$HOME/.local/state}/dogfiles/backups/wpscan-XXXXXX")
      mv "$HOME/.local/bin/wpscan" "$wpscan_backup/wpscan"
      printf 'Backed up WPScan launcher: %s/wpscan\n' "$wpscan_backup"
    fi
    printf '#!/usr/bin/env bash\nexec env -u GEM_HOME -u GEM_PATH RBENV_ROOT=%q RBENV_VERSION=%q %q exec wpscan "$@"\n' \
      "$HOME/.rbenv" "$WPSCAN_RUBY_VERSION" "$rbenv_bin" > "$HOME/.local/bin/wpscan"
    chmod 755 "$HOME/.local/bin/wpscan"
    clone_pinned https://github.com/sullo/nikto.git "$HOME/code/misc/nikto" "$NIKTO_REVISION"
    command -v go >/dev/null 2>&1 || packages golang-go
    go install "github.com/OJ/gobuster/v3@$GOBUSTER_VERSION"
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
    clone_pinned https://github.com/alacritty/alacritty.git "$tmp_dir/alacritty" "$ALACRITTY_REVISION"
    tic -xe alacritty,alacritty-direct "$tmp_dir/alacritty/extra/alacritty.info"
    rm -rf -- "$tmp_dir"; tmp_dir=
  fi
fi
printf '\nPost-installation complete. Open a new terminal for optional runtime integrations.\n'
