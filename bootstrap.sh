#!/usr/bin/env bash
# Standalone entry point: keep all mutations behind dry_run/configs_only checks.
set -Eeuo pipefail

usage() {
  cat <<'HELP'
Usage: bash bootstrap.sh [--dry-run] [--configs-only] [--include-monitors]

Install common tools, prepare SSH, clone ~/code/darius/dogfiles and link configs.
--dry-run          Inspect and print actions without changing the machine.
--configs-only     Only link configs from this local checkout (or the standard path).
--include-monitors Restore Omarchy monitor settings too (default: skip).
--help             Show this help.

Run as your normal user. System package installation uses sudo when necessary.
Optional runtimes, applications and security tools remain in install.sh.
HELP
}

say() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

detect_platform() {
  local release_file=${1:-/etc/os-release}
  case "$(uname -s)" in
    Darwin) platform=macos ;;
    Linux)
      # Check installed Omarchy before the generic distribution family.
      if have pacman && { pacman -Q omarchy >/dev/null 2>&1 ||
        [[ -d /usr/share/omarchy || -d "$HOME/.local/share/omarchy" ]]; }; then
        platform=omarchy
      elif [[ -r "$release_file" ]]; then
        local ID= ID_LIKE=
        . "$release_file"
        case " $ID $ID_LIKE " in
          *' debian '*|*' ubuntu '*|*' linuxmint '*) platform=debian ;;
          *) die "Unsupported Linux distribution: $ID" ;;
        esac
      else
        die 'Cannot identify this Linux distribution.'
      fi ;;
    *) die "Unsupported operating system: $(uname -s)" ;;
  esac
  say "Platform: $platform ($(uname -m))"
}

as_root() {
  if [[ $(id -u) == 0 ]]; then
    die 'Run bootstrap.sh as your normal user, not root.'
  fi
  have sudo || die 'sudo is required to install system packages.'
  # stdin may contain the rest of a piped bootstrap script.
  sudo -v </dev/tty
  sudo "$@"
}

validate_checkout() {
  [[ -e "$repo_dir" || -L "$repo_dir" ]] || return 0
  [[ -d "$repo_dir" ]] || die "Destination is not a directory: $repo_dir"
  if ! have git || { [[ "$platform" == macos ]] && ! xcode-select -p >/dev/null 2>&1; }; then
    [[ -e "$repo_dir/.git" ]] || die "Destination is not a Git checkout: $repo_dir"
    checkout_pending=true
    say 'Checkout identity validation is pending until Git and its prerequisites are available.'
    return
  fi
  local top remote
  top=$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null) ||
    die "Destination is not a Git checkout: $repo_dir"
  [[ "$(cd "$repo_dir" && pwd -P)" == "$(cd "$top" && pwd -P)" ]] ||
    die "Destination is inside another repository: $repo_dir"
  remote=$(git -C "$repo_dir" remote get-url origin 2>/dev/null) ||
    die "Existing checkout has no origin: $repo_dir"
  case "$remote" in
    https://github.com/panacotar/dogfiles|https://github.com/panacotar/dogfiles.git|git@github.com:panacotar/dogfiles.git|ssh://git@github.com/panacotar/dogfiles.git) ;;
    *) die "Destination belongs to another repository: $repo_dir" ;;
  esac
  checkout_pending=false
  say "Preserve existing checkout, branch, remotes and edits: $repo_dir"
}

find_brew() {
  if have brew; then brew_bin=$(command -v brew)
  elif [[ -x /opt/homebrew/bin/brew ]]; then brew_bin=/opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then brew_bin=/usr/local/bin/brew
  else brew_bin=
  fi
}

package_list() {
  case "$platform" in
    macos) packages=(git curl wget unzip zsh vim tealdeer lazygit tmux gnupg tig tree htop sqlite exiftool pkgconf gh jq ca-certificates) ;;
    debian)
      packages=(git curl wget unzip zsh vim tealdeer tmux gnupg tig tree htop sqlite3 libimage-exiftool-perl pkg-config gh jq openssh-client ca-certificates)
      if [[ -n ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then packages+=(xclip); fi ;;
    omarchy) packages=(git curl wget unzip zsh vim tealdeer lazygit tmux gnupg tig tree htop sqlite perl-image-exiftool pkgconf github-cli jq openssh ca-certificates) ;;
  esac
  # Several tldr implementations share the command; avoid replacing/conflicting
  # with a working one the user already has (e.g. tlrc installed through Brew).
  if have tldr; then
    local filtered=() package
    for package in "${packages[@]}"; do
      if [[ "$package" != tealdeer ]]; then filtered+=("$package"); fi
    done
    packages=("${filtered[@]}")
  fi
}

install_lazygit_binary() {
  if have lazygit; then return; fi
  local arch version asset url expected actual
  case "$(uname -m)" in
    x86_64|amd64) arch=x86_64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) die "No Lazygit binary configured for architecture $(uname -m)" ;;
  esac
  version=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -er '.tag_name')
  [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'Invalid Lazygit release version.'
  asset="lazygit_${version#v}_linux_${arch}.tar.gz"
  url="https://github.com/jesseduffield/lazygit/releases/download/$version"
  temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles.XXXXXX")
  curl -fsSL "$url/$asset" -o "$temp_dir/$asset"
  curl -fsSL "$url/checksums.txt" -o "$temp_dir/checksums.txt"
  expected=$(awk -v name="$asset" '$2 == name || $2 == "*" name {print $1}' "$temp_dir/checksums.txt")
  [[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || die "Missing checksum for $asset"
  actual=$(sha256sum "$temp_dir/$asset")
  [[ "${actual%% *}" == "$expected" ]] || die 'Lazygit checksum verification failed.'
  tar -xzf "$temp_dir/$asset" -C "$temp_dir" lazygit
  as_root install -m 0755 "$temp_dir/lazygit" /usr/local/bin/lazygit
  rm -rf -- "$temp_dir"
  temp_dir=
}

install_packages() {
  package_list
  say "Common packages ($platform): ${packages[*]}"
  if "$dry_run"; then
    case "$platform" in
      macos) say 'Would check Apple command-line tools; install Homebrew if missing, then missing formulae.' ;;
      debian) say 'Would refresh APT metadata, install missing packages and Lazygit (APT when available; otherwise a checksum-verified upstream binary).' ;;
      omarchy) say 'Would install missing packages with pacman -S --needed (no database refresh).' ;;
    esac
    say 'Would update the tldr cache.'
    return
  fi
  case "$platform" in
    macos)
      if ! xcode-select -p >/dev/null 2>&1; then
        xcode-select --install || true
        die 'Complete the Apple command-line tools installation, then rerun bootstrap.sh.'
      fi
      find_brew
      if [[ -z "$brew_bin" ]]; then
        temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles.XXXXXX")
        curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$temp_dir/homebrew.sh"
        /bin/bash "$temp_dir/homebrew.sh" </dev/tty
        rm -rf -- "$temp_dir"
        temp_dir=
        find_brew
        [[ -n "$brew_bin" ]] || die 'Homebrew installation did not produce a brew executable.'
      fi
      eval "$("$brew_bin" shellenv)"
      local missing=() package
      for package in "${packages[@]}"; do
        if ! "$brew_bin" list --formula "$package" >/dev/null 2>&1; then missing+=("$package"); fi
      done
      if [[ ${#missing[@]} -gt 0 ]]; then HOMEBREW_NO_AUTO_UPDATE=1 "$brew_bin" install "${missing[@]}"; fi ;;
    debian)
      as_root apt-get update
      local apt_missing=() apt_package
      for apt_package in "${packages[@]}"; do
        if [[ $(dpkg-query -W -f='${Status}' "$apt_package" 2>/dev/null || true) != 'install ok installed' ]]; then
          apt_missing+=("$apt_package")
        fi
      done
      if [[ ${#apt_missing[@]} -gt 0 ]]; then as_root apt-get install -y "${apt_missing[@]}"; fi
      if ! have lazygit; then
        if apt-cache show lazygit >/dev/null 2>&1 && [[ $(apt-cache policy lazygit) != *'Candidate: (none)'* ]]; then
          as_root apt-get install -y lazygit
        else
          install_lazygit_binary
        fi
      fi ;;
    omarchy) as_root pacman -S --needed --noconfirm "${packages[@]}" ;;
  esac
  if ! tldr --update; then say 'Warning: tldr cache update failed; retry with tldr --update.'; fi
}

apple_ssh_add() { /usr/bin/ssh-add --apple-use-keychain "$@"; }

setup_ssh() {
  local key="$HOME/.ssh/github_id_ed25519" config="$HOME/.ssh/config" saved_dir=
  if [[ -e "$key" || -L "$key" ]]; then
    say "Skip SSH setup: $key already exists."
    return
  fi
  # Preflight before generating a key; never overwrite an orphaned public key.
  [[ ! -e "$key.pub" && ! -L "$key.pub" ]] || die "Public key exists without its private key: $key.pub"
  if [[ -e "$config" || -L "$config" ]]; then
    [[ -f "$config" ]] || die "SSH config is not a regular file: $config"
  fi
  if "$dry_run"; then
    say "Would generate $key (interactive passphrase), configure its GitHub identity and load it into an SSH agent."
    if [[ -e "$config" ]]; then say "Would back up SSH config under $state_root/dogfiles/backups/."; fi
    say 'Would print the public key and manual GitHub registration instructions.'
    return
  fi
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -f "$key" -C "dogfiles-$(hostname)" </dev/tty
  # Prepending selects this identity before broad Host * defaults; the old file
  # remains intact below it. Keep an existing symlink's target intact as well.
  temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles.XXXXXX")
  {
    printf 'Host github.com\n  HostName github.com\n  User git\n  IdentityFile ~/.ssh/github_id_ed25519\n  AddKeysToAgent yes\n'
    if [[ "$platform" == macos ]]; then printf '  UseKeychain yes\n'; fi
    printf '\nHost *\n'
    if [[ -f "$config" ]]; then cat "$config"; fi
  } > "$temp_dir/ssh-config"
  if [[ -e "$config" || -L "$config" ]]; then
    mkdir -p "$state_root/dogfiles/backups"
    saved_dir=$(mktemp -d "$state_root/dogfiles/backups/ssh-$(date +%Y%m%d-%H%M%S)-XXXXXX")
    mv "$config" "$saved_dir/config"
    say "Backed up SSH config: $saved_dir/config"
  fi
  cp "$temp_dir/ssh-config" "$config"
  chmod 600 "$config"
  rm -rf -- "$temp_dir"
  temp_dir=
  # ssh-add returns 1 for a reachable agent with no keys, 2 for no agent.
  local agent_status=0
  ssh-add -l >/dev/null 2>&1 || agent_status=$?
  if [[ "$agent_status" == 2 ]]; then eval "$(ssh-agent -s)"; fi
  if [[ "$platform" == macos ]]; then
    apple_ssh_add "$key" </dev/tty
  else
    ssh-add "$key" </dev/tty
  fi
  new_ssh_key=true
  say 'Add this public key at https://github.com/settings/ssh/new (authentication key):'
  cat "$key.pub"
  say 'If using SSH commit signing, also register it as a signing key.'
}

clone_checkout() {
  if [[ -d "$repo_dir" ]]; then return; fi
  if "$dry_run"; then
    say "Would create $(dirname "$repo_dir") and clone https://github.com/panacotar/dogfiles.git into $repo_dir."
    say 'Would set the new checkout origin to git@github.com:panacotar/dogfiles.git.'
    return
  fi
  mkdir -p "$(dirname "$repo_dir")"
  git clone https://github.com/panacotar/dogfiles.git "$repo_dir"
  git -C "$repo_dir" remote set-url origin git@github.com:panacotar/dogfiles.git
}

collect_links() {
  sources=(); targets=()
  local manifests=(common) manifest source kind relative extra target parent
  if [[ "$platform" != omarchy ]]; then manifests+=(shell); fi
  if [[ "$platform" == macos ]]; then manifests+=(macos); fi
  for manifest in "${manifests[@]}"; do
    [[ -f "$repo_dir/conf/$manifest.links" ]] || die "Missing manifest: $repo_dir/conf/$manifest.links"
    while IFS='|' read -r source kind relative extra || [[ -n "$source" ]]; do
      [[ -z "$source" || "$source" == \#* ]] && continue
      [[ -z "$extra" && -n "$relative" && "$source" != /* && "/$source/" != */../* && "$relative" != /* && "/$relative/" != */../* ]] || die "Invalid link entry in $manifest.links"
      case "$kind" in
        home) target="$HOME/$relative" ;;
        config) target="$config_root/$relative" ;;
        *) die "Unknown destination type: $kind" ;;
      esac
      [[ -f "$repo_dir/conf/$source" && ! -L "$repo_dir/conf/$source" ]] || die "Missing regular config: $source"
      [[ ! -d "$target" || -L "$target" ]] || die "Expected a file, found directory: $target"
      parent=$(dirname "$target")
      while [[ "$parent" != / ]]; do
        [[ ! -e "$parent" && ! -L "$parent" || -d "$parent" ]] || die "Config parent is not a directory: $parent"
        parent=$(dirname "$parent")
      done
      sources+=("$repo_dir/conf/$source"); targets+=("$target")
    done < "$repo_dir/conf/$manifest.links"
  done
}

link_configs() {
  if [[ ! -d "$repo_dir" || ${checkout_pending:-false} == true ]]; then
    say 'Config manifest/source validation is pending until the checkout exists and its identity is verified.'
    say "Would link shared Git/Vim/tmux configs from $repo_dir/conf."
    if [[ "$platform" == omarchy ]]; then
      say 'Would run bash omarchy/install.sh --dry-run (monitor settings skipped unless --include-monitors).'
    else
      say 'Would link Zsh, aliases, custom commands, Ruby tool configs and Alacritty configs.'
    fi
    say "Would back up conflicting files/links under $state_root/dogfiles/backups/."
    return
  fi
  collect_links
  local i source target backup_dir=
  for ((i=0; i<${#sources[@]}; i++)); do
    source=${sources[$i]}; target=${targets[$i]}
    if [[ -L "$target" && "$target" -ef "$source" ]]; then
      say "Already linked: $target"
      continue
    fi
    if [[ -e "$target" || -L "$target" ]]; then
      if "$dry_run"; then
        say "Would back up: $target (under $state_root/dogfiles/backups/)"
      else
        if [[ -z "$backup_dir" ]]; then
          mkdir -p "$state_root/dogfiles/backups"
          backup_dir=$(mktemp -d "$state_root/dogfiles/backups/bootstrap-$(date +%Y%m%d-%H%M%S)-XXXXXX")
        fi
        # The full absolute path also avoids HOME/XDG destination collisions.
        mkdir -p "$backup_dir$(dirname "$target")"
        mv "$target" "$backup_dir$target"
        say "Backed up: $target -> $backup_dir$target"
      fi
    fi
    if "$dry_run"; then
      say "Would link: $target -> $source"
    else
      mkdir -p "$(dirname "$target")"
      ln -s "$source" "$target"
      say "Linked: $target -> $source"
    fi
  done
  if [[ "$platform" == omarchy ]]; then
    local args=()
    if "$dry_run"; then args+=(--dry-run); fi
    if "$include_monitors"; then args+=(--include-monitors); fi
    bash "$repo_dir/omarchy/install.sh" ${args[@]+"${args[@]}"}
  fi
}

clone_plugin() {
  local url=$1 destination=$2
  if [[ -d "$destination/.git" ]]; then
    say "Already installed: $destination"
  elif [[ -e "$destination" || -L "$destination" ]]; then
    die "Plugin destination already exists but is not a checkout: $destination"
  else
    mkdir -p "$(dirname "$destination")"
    git clone --depth 1 "$url" "$destination"
  fi
}

setup_plugins() {
  if "$dry_run"; then
    say 'Would install TPM and the tmux plugins configured in tmux.conf (preserving existing checkouts).'
    if [[ "$platform" != omarchy ]]; then say 'Would install Oh My Zsh, zsh-autosuggestions and zsh-syntax-highlighting if missing.'; fi
    return
  fi
  if [[ "$platform" != omarchy ]]; then
    if [[ ! -e "$HOME/.oh-my-zsh" ]]; then
      temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles.XXXXXX")
      curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$temp_dir/ohmyzsh.sh"
      ZSH="$HOME/.oh-my-zsh" ZDOTDIR="$HOME" sh "$temp_dir/ohmyzsh.sh" --unattended --keep-zshrc
      rm -rf -- "$temp_dir"
      temp_dir=
    fi
    [[ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]] || die 'Existing Oh My Zsh installation is incomplete.'
    clone_plugin https://github.com/zsh-users/zsh-autosuggestions.git "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
    clone_plugin https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  fi
  # Clone the manifest's declared plugins directly. This avoids starting a tmux
  # server or modifying a user's running sessions just to install plugins.
  local plugin
  while IFS= read -r plugin; do
    [[ "$plugin" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "Invalid tmux plugin: $plugin"
    clone_plugin "https://github.com/$plugin.git" "$HOME/.tmux/plugins/${plugin##*/}"
  done < <(sed -n "s/^set -g @plugin '\([^']*\)'.*/\1/p" "$repo_dir/conf/tmux.conf")
}

setup_login_shell() {
  if [[ "$platform" == omarchy ]]; then say 'Preserve Omarchy login shell and shell configuration.'; return; fi
  if "$dry_run"; then say 'Would validate Zsh startup and make Zsh the login shell if necessary.'; return; fi
  local zsh_bin current_shell
  zsh_bin=$(command -v zsh)
  # Validate the installed config before changing the login shell.
  zsh -n "$HOME/.zshrc"
  ZDOTDIR="$HOME" zsh -ic 'exit' </dev/null
  current_shell=${SHELL:-}
  if [[ "$platform" == macos ]]; then
    current_shell=$(dscl . -read "/Users/$(id -un)" UserShell | awk '{print $2}')
  elif have getent; then
    current_shell=$(getent passwd "$(id -un)" | cut -d: -f7)
  fi
  if [[ "$current_shell" == "$zsh_bin" ]]; then say 'Zsh is already the login shell.'; return; fi
  if ! grep -Fxq "$zsh_bin" /etc/shells; then
    if ! printf '%s\n' "$zsh_bin" | as_root tee -a /etc/shells >/dev/null; then
      say "Warning: add $zsh_bin to /etc/shells, then run: chsh -s $zsh_bin"
      return
    fi
  fi
  if ! chsh -s "$zsh_bin" </dev/tty; then
    say "Warning: change the login shell manually with: chsh -s $zsh_bin"
  fi
}

verify_tools() {
  local tool missing=false
  for tool in git curl wget unzip zsh vim tldr lazygit tmux gpg tig tree htop sqlite3 exiftool pkg-config gh jq ssh; do
    if ! have "$tool"; then say "Missing command after installation: $tool"; missing=true; fi
  done
  if "$missing"; then die 'Some common tools are unavailable; check the package output above.'; fi
}

main() {
  dry_run=false; configs_only=false; include_monitors=false; new_ssh_key=false; checkout_pending=false
  temp_dir=
  trap 'if [[ -n "$temp_dir" ]]; then rm -rf -- "$temp_dir"; fi' EXIT
  trap 'printf "Bootstrap failed at line %s. Fix the reported issue and rerun; completed steps are preserved.\n" "$LINENO" >&2' ERR
  local arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=true ;;
      --configs-only) configs_only=true ;;
      --include-monitors) include_monitors=true ;;
      --help|-h) usage; return ;;
      *) usage >&2; die "Unknown option: $arg" ;;
    esac
  done
  [[ "$HOME" == /* ]] || die 'HOME must be absolute.'
  config_root=${XDG_CONFIG_HOME:-$HOME/.config}
  state_root=${XDG_STATE_HOME:-$HOME/.local/state}
  [[ "$config_root" == /* && "$state_root" == /* ]] || die 'XDG paths must be absolute.'
  detect_platform
  if "$include_monitors" && [[ "$platform" != omarchy ]]; then die '--include-monitors is only supported on Omarchy.'; fi
  repo_dir="$HOME/code/darius/dogfiles"
  if "$configs_only" && [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
    repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
  fi
  if ! "$configs_only"; then validate_checkout; fi
  say "Checkout: $repo_dir"
  if "$dry_run"; then say 'DRY RUN: no changes will be made.'; fi
  if "$configs_only"; then
    [[ -d "$repo_dir/conf" ]] || die '--configs-only requires a local dogfiles checkout.'
    link_configs
  else
    if ! "$dry_run"; then
      [[ $(id -u) != 0 ]] || die 'Run bootstrap.sh as your normal user, not root.'
      [[ -r /dev/tty ]] && ( : </dev/tty ) 2>/dev/null || die 'An interactive terminal is required (or use --dry-run).'
    fi
    install_packages
    if "$checkout_pending" && ! "$dry_run"; then validate_checkout; fi
    setup_ssh
    clone_checkout
    # Oh My Zsh must exist before validating the linked .zshrc.
    setup_plugins
    link_configs
    setup_login_shell
    if ! "$dry_run"; then verify_tools; fi
  fi
  say "Finished. Checkout: $repo_dir"
  if ! "$dry_run"; then
    if "$new_ssh_key"; then say 'Manual step: register the printed public key on GitHub, then test: ssh -T git@github.com'; fi
    say 'Open a new terminal to use the configuration.'
    if [[ "$platform" != omarchy ]]; then printf 'Optional post-installation: bash %q\n' "$repo_dir/install.sh"; fi
  fi
}

# Keep this last: piped input defines the complete program before any work starts.
main "$@"
