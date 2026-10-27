#!/usr/bin/env bash
# First-machine setup, in order:
#  1. Parse options, validate HOME/XDG paths, and detect macOS, Debian-family Linux,
#     or installed Omarchy. Require a normal user/terminal for a full installation.
#  2. Validate an existing ~/code/darius/dogfiles checkout, preserving its branch,
#     remotes and edits; defer identity checks until Git is available if necessary.
#  3. Install missing prerequisites/common tools with Homebrew, APT or Pacman:
#     git, curl, wget, unzip, zsh, vim, tldr (tealdeer), lazygit, tmux, gpg, tig,
#     tree, htop, sqlite3, exiftool, pkg-config, gh, jq, and CA certificates.
#     Linux also gets OpenSSH; Debian-family X11 sessions also get xclip.
#     macOS checks Apple command-line tools and installs Homebrew if missing.
#     Debian refreshes APT metadata; Omarchy uses its existing Pacman database.
#  4. Use a pinned, checksum-verified x86_64/ARM64 Lazygit release if APT cannot provide it,
#     preserve an existing tldr client, and update the tldr cache.
#  5. Reuse ~/.ssh/github_id_ed25519 if present. Otherwise generate it,
#     back up/configure the GitHub SSH identity, and load the key into an agent
#     (with Keychain on macOS). Share the agent with future Zsh sessions, and
#     print new public keys for manual GitHub registration.
#  6. Create ~/code/darius and clone dogfiles over HTTPS if absent; set only a new
#     checkout's origin to SSH. Existing checkout remotes are left as they are.
#  7. On all platforms, install Oh My Zsh while keeping .zshrc, plus autosuggestions
#     and syntax highlighting. On all platforms, install TPM and the tmux plugins
#     declared in conf/tmux.conf at fixed commits, preserving existing checkouts.
#     Source pins are in scripts/sources.sh; tmux pins are in conf/tmux.conf.
#  8. Validate conf/*.links manifests and config destinations, back up conflicts
#     under the XDG state directory, and create symlinks for Git/Vim/tmux plus
#     personal shell/application configs. Leave correct links untouched.
#     On macOS, link conf/macos as ~/.macos; applying its settings is install.sh's
#     responsibility. Git identity/ignore/signing come from the linked gitconfig.
#  9. On Omarchy, delegate desktop/terminal config to omarchy/install.sh, giving
#     personal configs priority, and restore monitor settings only with --include-monitors.
# 10. On all platforms, validate Zsh startup and make it the login shell; print a
#     manual command if blocked. Update any active/default tmux server so future
#     panes use Zsh. Verify installed commands and print session-switch instructions.
#
# --dry-run previews these steps without changes, downloads, logs or prompts.
# --configs-only only applies config links from a local checkout; both flags can
# be combined. Temporary downloads are cleaned up on exit.
# Security tools (including WPScan), runtimes and optional apps belong to the
# separate install.sh. This script does not configure or trust third-party Brew
# taps; Homebrew may still print diagnostics about taps already on the machine.
#
# Standalone entry point: keep all mutations behind dry_run/configs_only checks.
set -Eeuo pipefail

# Edit these package lists to customize the bootstrap. Platform lists are added
# to COMMON_PACKAGES; use native package names for that platform.
readonly -a COMMON_PACKAGES=(
  git curl wget unzip zsh vim tealdeer tmux gnupg tig tree htop jq ca-certificates
)
readonly -a MACOS_PACKAGES=(
  lazygit sqlite exiftool pkgconf gh
)
readonly -a DEBIAN_PACKAGES=(
  sqlite3 libimage-exiftool-perl pkg-config gh openssh-client
)
# Lazygit is handled separately on Debian: APT when available, otherwise a binary.
readonly -a DEBIAN_X11_PACKAGES=(
  xclip
)
readonly -a OMARCHY_PACKAGES=(
  lazygit sqlite perl-image-exiftool pkgconf github-cli openssh
)

# Pins needed before a checkout exists. Other source pins: scripts/sources.sh
# and conf/tmux.conf. Refresh versions and hashes together after review.
readonly HOMEBREW_INSTALL_REVISION=85d1a3fc80d8a63932f632aca8f787de11d14a64
readonly HOMEBREW_INSTALL_SHA256=5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148
readonly LAZYGIT_VERSION=v0.66.2
readonly LAZYGIT_ARM64_SHA256=79a3161eeb642f0473e23db6341f7baabd4a5933e921a9c1167c5d5c765c41a4
readonly LAZYGIT_X86_64_SHA256=158efc9ddfa1241fab5fb3526bb442c8dc6c4b1904d73213b9e4e93e03c52034

usage() {
  cat <<'HELP'
Usage: bash bootstrap.sh [--dry-run] [--configs-only] [--include-monitors]

Install common tools, Oh My Zsh, set Zsh as the login shell, and link configs.
Personal conf/ settings take priority over Omarchy desktop/terminal settings.
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

# A curl-piped bootstrap has no checkout yet. Keep minimal announcements available
# without fetching helpers, including during dry-run; use shared styling once local.
trumpet() { printf '\n#################################\n %s \n#################################\n' "$1"; }
progress_comm() { printf '\n-----> %s\n' "$1"; }
load_output_helpers() {
  local checkout=$1
  if [[ -f "$checkout/scripts/output.sh" ]]; then
    source "$checkout/scripts/output.sh"
    init_output
  fi
}

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
  packages=(${COMMON_PACKAGES[@]+"${COMMON_PACKAGES[@]}"})
  case "$platform" in
    macos) packages+=(${MACOS_PACKAGES[@]+"${MACOS_PACKAGES[@]}"}) ;;
    debian)
      packages+=(${DEBIAN_PACKAGES[@]+"${DEBIAN_PACKAGES[@]}"})
      if [[ -n ${DISPLAY:-} && -z ${WAYLAND_DISPLAY:-} ]]; then
        packages+=(${DEBIAN_X11_PACKAGES[@]+"${DEBIAN_X11_PACKAGES[@]}"})
      fi ;;
    omarchy) packages+=(${OMARCHY_PACKAGES[@]+"${OMARCHY_PACKAGES[@]}"}) ;;
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
  progress_comm 'Installing Lazygit from a checksum-verified release...'
  local arch asset url expected actual
  case "$(uname -m)" in
    x86_64|amd64) arch=x86_64; expected=$LAZYGIT_X86_64_SHA256 ;;
    aarch64|arm64) arch=arm64; expected=$LAZYGIT_ARM64_SHA256 ;;
    *) die "No Lazygit binary configured for architecture $(uname -m)" ;;
  esac
  asset="lazygit_${LAZYGIT_VERSION#v}_linux_${arch}.tar.gz"
  url="https://github.com/jesseduffield/lazygit/releases/download/$LAZYGIT_VERSION"
  temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles.XXXXXX")
  curl -fsSL "$url/$asset" -o "$temp_dir/$asset"
  actual=$(sha256sum "$temp_dir/$asset")
  [[ "${actual%% *}" == "$expected" ]] || die 'Lazygit checksum verification failed.'
  tar -xzf "$temp_dir/$asset" -C "$temp_dir" lazygit
  as_root install -m 0755 "$temp_dir/lazygit" /usr/local/bin/lazygit
  rm -rf -- "$temp_dir"
  temp_dir=
}

install_packages() {
  trumpet 'Installing common CLI tools...'
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
      progress_comm 'Checking Apple command-line tools and Homebrew...'
      if ! xcode-select -p >/dev/null 2>&1; then
        xcode-select --install || true
        die 'Complete the Apple command-line tools installation, then rerun bootstrap.sh.'
      fi
      find_brew
      if [[ -z "$brew_bin" ]]; then
        progress_comm 'Installing Homebrew...'
        temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles.XXXXXX")
        curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/$HOMEBREW_INSTALL_REVISION/install.sh" -o "$temp_dir/homebrew.sh"
        local installer_checksum
        installer_checksum=$(shasum -a 256 "$temp_dir/homebrew.sh")
        [[ ${installer_checksum%% *} == "$HOMEBREW_INSTALL_SHA256" ]] || die 'Homebrew installer checksum verification failed.'
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
      if [[ ${#missing[@]} -gt 0 ]]; then
        progress_comm "Installing Homebrew formulae: ${missing[*]}"
        HOMEBREW_NO_AUTO_UPDATE=1 "$brew_bin" install "${missing[@]}"
      else
        say 'All configured Homebrew formulae are already installed.'
      fi ;;
    debian)
      progress_comm 'Updating the APT package index...'
      as_root apt-get update
      local apt_missing=() apt_package
      for apt_package in "${packages[@]}"; do
        if [[ $(dpkg-query -W -f='${Status}' "$apt_package" 2>/dev/null || true) != 'install ok installed' ]]; then
          apt_missing+=("$apt_package")
        fi
      done
      if [[ ${#apt_missing[@]} -gt 0 ]]; then
        progress_comm "Installing APT packages: ${apt_missing[*]}"
        as_root apt-get install -y "${apt_missing[@]}"
      else
        say 'All configured APT packages are already installed.'
      fi
      if ! have lazygit; then
        if apt-cache show lazygit >/dev/null 2>&1 && [[ $(apt-cache policy lazygit) != *'Candidate: (none)'* ]]; then
          progress_comm 'Installing Lazygit with APT...'
          as_root apt-get install -y lazygit
        else
          install_lazygit_binary
        fi
      fi ;;
    omarchy)
      progress_comm 'Installing missing Pacman packages without refreshing the database...'
      as_root pacman -S --needed --noconfirm "${packages[@]}" ;;
  esac
  progress_comm 'Updating the tldr cache...'
  if ! tldr --update; then say 'Warning: tldr cache update failed; retry with tldr --update.'; fi
}

apple_ssh_add() { /usr/bin/ssh-add --apple-use-keychain "$@"; }

load_github_key() {
  local key=$1 agent_status=0 cache="$HOME/.ssh/environment-$(hostname -s)" cache_temp
  if "$dry_run"; then
    say "Would reuse/start an SSH agent and load $key if it is not already loaded."
    return
  fi
  ssh-add -l >/dev/null 2>&1 || agent_status=$?
  if [[ "$agent_status" == 2 && -f "$cache" ]]; then
    # Share the environment cache with Oh My Zsh's ssh-agent plugin.
    source "$cache" >/dev/null
    agent_status=0
    ssh-add -l >/dev/null 2>&1 || agent_status=$?
  fi
  if [[ "$agent_status" == 2 ]]; then eval "$(ssh-agent -s)"; fi
  cache_temp=$(mktemp "$HOME/.ssh/.dogfiles-agent.XXXXXX")
  {
    printf 'export SSH_AUTH_SOCK=%q\n' "$SSH_AUTH_SOCK"
    if [[ -n ${SSH_AGENT_PID:-} ]]; then printf 'export SSH_AGENT_PID=%q\n' "$SSH_AGENT_PID"; fi
  } > "$cache_temp"
  chmod 600 "$cache_temp"
  mv "$cache_temp" "$cache"
  if [[ -f "$key.pub" ]] && ssh-add -T "$key.pub" >/dev/null 2>&1; then
    say 'GitHub key is already loaded in the SSH agent.'
    return
  fi
  progress_comm 'Loading the GitHub key into the SSH agent (unlock once per agent session)...'
  if [[ "$platform" == macos ]]; then
    apple_ssh_add "$key" </dev/tty
  else
    ssh-add "$key" </dev/tty
  fi
}

setup_ssh() {
  trumpet 'Setting up GitHub SSH access...'
  local key="$HOME/.ssh/github_id_ed25519" config="$HOME/.ssh/config" saved_dir=
  if [[ -e "$key" || -L "$key" ]]; then
    say "Preserve existing SSH key and config: $key"
    load_github_key "$key"
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
  progress_comm "Generating $key..."
  ssh-keygen -t ed25519 -f "$key" -C "dogfiles-$(hostname)" </dev/tty
  # Prepending selects this identity before broad Host * defaults; the old file
  # remains intact below it. Keep an existing symlink's target intact as well.
  temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles.XXXXXX")
  {
    # Leave HostName unset so existing alternate endpoints (e.g. SSH over 443)
    # retain their hostname as well as their port and proxy configuration.
    printf 'Host github.com\n  User git\n  IdentityFile ~/.ssh/github_id_ed25519\n  AddKeysToAgent yes\n'
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
  load_github_key "$key"
  new_ssh_key=true
  say 'Add this public key at https://github.com/settings/ssh/new (authentication key):'
  cat "$key.pub"
  say 'If using SSH commit signing, also register it as a signing key.'
}

clone_checkout() {
  trumpet 'Preparing the dogfiles checkout...'
  if [[ -d "$repo_dir" ]]; then say "Using existing checkout: $repo_dir"; return; fi
  if "$dry_run"; then
    say "Would create $(dirname "$repo_dir") and clone https://github.com/panacotar/dogfiles.git into $repo_dir."
    say 'Would set the new checkout origin to git@github.com:panacotar/dogfiles.git.'
    return
  fi
  mkdir -p "$(dirname "$repo_dir")"
  progress_comm "Cloning dogfiles into $repo_dir..."
  git clone https://github.com/panacotar/dogfiles.git "$repo_dir"
  git -C "$repo_dir" remote set-url origin git@github.com:panacotar/dogfiles.git
}

collect_links() {
  sources=(); targets=()
  local manifests=(common shell) manifest source kind relative extra target parent
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
      # Only Omarchy needs a wrapper to select bootstrap's plugin directory.
      if [[ "$platform" == omarchy && "$kind" == config && "$relative" == tmux/tmux.conf && "$source" == tmux.conf ]]; then
        source=tmux-omarchy.conf
      fi
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
  trumpet 'Linking configuration files...'
  if [[ ! -d "$repo_dir" || ${checkout_pending:-false} == true ]]; then
    say 'Config manifest/source validation is pending until the checkout exists and its identity is verified.'
    say "Would link shared Git/Vim/tmux configs from $repo_dir/conf."
    if [[ "$platform" == omarchy ]]; then
      say 'Would run bash omarchy/install.sh --dry-run (monitor settings skipped unless --include-monitors).'
    fi
    say 'Would link Zsh, aliases, custom commands, Ruby tool configs and Alacritty configs (personal configs take priority).'
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
    for target in "${targets[@]}"; do
      if [[ "$target" == "$config_root/"* ]]; then
        args+=(--exclude-config "${target#"$config_root/"}")
      fi
    done
    progress_comm 'Processing Omarchy desktop and terminal configuration...'
    bash "$repo_dir/omarchy/install.sh" ${args[@]+"${args[@]}"}
  fi
}

setup_plugins() {
  trumpet 'Installing shell and tmux plugins...'
  if "$dry_run"; then
    say 'Would install TPM and the tmux plugins configured in tmux.conf at pinned commits (preserving existing checkouts).'
    say 'Would install Oh My Zsh, zsh-autosuggestions and zsh-syntax-highlighting at pinned commits if missing.'
    return
  fi
  source "$repo_dir/scripts/sources.sh"
  if [[ ! -e "$HOME/.oh-my-zsh" ]]; then
    progress_comm 'Installing Oh My Zsh...'
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles.XXXXXX")
    clone_pinned https://github.com/ohmyzsh/ohmyzsh.git "$temp_dir/ohmyzsh" "$OH_MY_ZSH_REVISION"
    # The official installer fetches a branch. Give it a local branch at the
    # verified commit so its second fetch cannot silently install newer code.
    git -C "$temp_dir/ohmyzsh" branch dogfiles-pinned "$OH_MY_ZSH_REVISION"
    ZSH="$HOME/.oh-my-zsh" ZDOTDIR="$HOME" REPO=ohmyzsh/ohmyzsh \
      REMOTE="file://$temp_dir/ohmyzsh" BRANCH=dogfiles-pinned \
      sh "$temp_dir/ohmyzsh/tools/install.sh" --unattended --keep-zshrc
    [[ $(git -C "$HOME/.oh-my-zsh" rev-parse HEAD) == "$OH_MY_ZSH_REVISION" ]] || die 'Oh My Zsh revision verification failed.'
    git -C "$HOME/.oh-my-zsh" checkout --detach "$OH_MY_ZSH_REVISION"
    git -C "$HOME/.oh-my-zsh" remote set-url origin https://github.com/ohmyzsh/ohmyzsh.git
    git -C "$HOME/.oh-my-zsh" config oh-my-zsh.branch master
    rm -rf -- "$temp_dir"
    temp_dir=
  elif [[ -d "$HOME/.oh-my-zsh/.git" ]]; then
    check_existing_revision "$HOME/.oh-my-zsh" "$OH_MY_ZSH_REVISION"
  fi
  [[ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]] || die 'Existing Oh My Zsh installation is incomplete.'
  clone_pinned https://github.com/zsh-users/zsh-autosuggestions.git "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" "$ZSH_AUTOSUGGESTIONS_REVISION"
  clone_pinned https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" "$ZSH_SYNTAX_HIGHLIGHTING_REVISION"
  # Clone the manifest's declared plugins directly. This avoids starting a tmux
  # server or modifying a user's running sessions just to install plugins.
  local entry plugin revision
  while IFS= read -r entry; do
    plugin=${entry%%#*}; revision=${entry#*#}
    [[ "$plugin" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "Invalid tmux plugin: $plugin"
    [[ "$entry" == *'#'* && "$revision" =~ ^[0-9a-f]{40}$ ]] || die "Missing commit pin for tmux plugin: $plugin"
    clone_pinned "https://github.com/$plugin.git" "$HOME/.tmux/plugins/${plugin##*/}" "$revision"
  done < <(sed -n "s/^set -g @plugin '\([^']*\)'.*/\1/p" "$repo_dir/conf/tmux.conf")
}

setup_login_shell() {
  trumpet 'Checking the login shell...'
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

setup_tmux_shell() {
  trumpet 'Updating the tmux shell...'
  if "$dry_run"; then
    say 'Would set Zsh as the default shell and SHELL for new panes in the active/default tmux server, if running.'
    if [[ "$platform" == omarchy ]]; then say 'Would reload the Omarchy tmux wrapper to activate installed plugins in that server.'; fi
    return
  fi
  # has-session only inspects an existing server; never start one during setup.
  if ! tmux has-session 2>/dev/null; then
    say 'No running tmux sessions to update; new servers will use the linked config.'
    return
  fi
  if [[ "$platform" == omarchy ]]; then
    # The wrapper selects the installed plugin directory before TPM is loaded.
    tmux source-file "$config_root/tmux/tmux.conf"
  fi
  local zsh_bin
  zsh_bin=$(command -v zsh)
  tmux set-option -g default-shell "$zsh_bin"
  tmux set-environment -g SHELL "$zsh_bin"
  say 'Existing tmux server updated: new panes and windows will use Zsh.'
}

verify_tools() {
  trumpet 'Verifying common CLI commands...'
  local tool missing=false
  for tool in git curl wget unzip zsh vim tldr lazygit tmux gpg tig tree htop sqlite3 exiftool pkg-config gh jq ssh; do
    if ! have "$tool"; then say "Missing command after installation: $tool"; missing=true; fi
  done
  if "$missing"; then die 'Some common tools are unavailable; check the package output above.'; fi
  say 'All common CLI commands are available.'
}

main() {
  dry_run=false; configs_only=false; include_monitors=false; new_ssh_key=false; checkout_pending=false
  temp_dir=
  trap 'if [[ -n "$temp_dir" ]]; then rm -rf -- "$temp_dir"; fi' EXIT
  trap 'printf "Bootstrap failed at line %s. Fix the reported issue and rerun; completed steps are preserved.\n" "$LINENO" >&2' ERR
  local arg local_checkout
  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=true ;;
      --configs-only) configs_only=true ;;
      --include-monitors) include_monitors=true ;;
      --help|-h) usage; return ;;
      *) usage >&2; die "Unknown option: $arg" ;;
    esac
  done
  if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
    local_checkout=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
    load_output_helpers "$local_checkout"
  fi
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
  if ! "$checkout_pending"; then load_output_helpers "$repo_dir"; fi
  say "Checkout: $repo_dir"
  if "$dry_run"; then say 'DRY RUN: no changes will be made.'; fi
  trumpet "Dogfiles setup: $platform"
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
    load_output_helpers "$repo_dir"
    # Oh My Zsh must exist before validating the linked .zshrc.
    setup_plugins
    link_configs
    setup_login_shell
    setup_tmux_shell
    if "$dry_run"; then
      trumpet 'Verifying common CLI commands...'
      say 'Would verify the installed CLI commands.'
    else
      verify_tools
    fi
  fi
  if "$dry_run"; then trumpet 'Setup preview complete'; else trumpet 'Dogfiles setup complete'; fi
  say "Finished. Checkout: $repo_dir"
  if ! "$dry_run"; then
    if "$new_ssh_key"; then say 'Manual step: register the printed public key on GitHub, then test: ssh -T git@github.com'; fi
    if ! "$configs_only"; then
      say 'Open a new tmux pane/window to use Zsh and your aliases.'
      say 'Existing shell processes stay unchanged. To switch the current shell, run:'
      printf '  export SHELL=%q; exec "$SHELL" -l\n' "$(command -v zsh)"
      say 'Log out of the desktop and log back in to refresh its inherited shell environment.'
    else
      say 'Config links updated. Run the full bootstrap to install Zsh/plugins and update the login/tmux shell.'
    fi
    if [[ "$platform" != omarchy ]]; then printf 'Optional post-installation: bash %q\n' "$repo_dir/install.sh"; fi
  fi
}

# Keep this last: piped input defines the complete program before any work starts.
main "$@"
