#!/usr/bin/env bash
# Fixed upstream commits for code installed outside native package managers.
# Update these deliberately after reviewing upstream changes. Existing checkouts
# are reported and preserved, including local edits; new checkouts are detached.
readonly OH_MY_ZSH_REVISION=d2b7f557cceaddb16ba89bbf8200d8a8df35c4d8
readonly ZSH_AUTOSUGGESTIONS_REVISION=85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5
readonly ZSH_SYNTAX_HIGHLIGHTING_REVISION=e6683f20e5c38d3e5447f45845d04ddda75d0f23
readonly RBENV_REVISION=07e9b1e297a5977298c6aadc9971ae0e9eb7f0dc
readonly RUBY_BUILD_REVISION=b6a92c15f0df872047c74f7dfa0b92dfd4de8a92
readonly PYENV_REVISION=abc069cebac3734e6f02f987fcbd571ad657db50
readonly PYENV_VIRTUALENV_REVISION=7d821a62d6eeae21a451141c41898be1ed4ed147
readonly NVM_REVISION=e780535240ee3ba67048b434cec6f7f509ee7b31
readonly NIKTO_REVISION=312645d873478a77986627ab1fc8cffe595e85d4
readonly ALACRITTY_REVISION=934831baf1adb9db76b35630002b2b54a960406f
readonly GOBUSTER_VERSION=v3.8.2
readonly WPSCAN_VERSION=4.1.0

check_existing_revision() {
  local destination=$1 revision=$2 actual
  actual=$(git -C "$destination" rev-parse HEAD) || return
  if [[ "$actual" != "$revision" ]]; then
    printf 'Warning: preserving existing checkout %s at %s; configured pin is %s. Review it manually.\n' "$destination" "$actual" "$revision" >&2
  fi
}

clone_pinned() {
  local url=$1 destination=$2 revision=$3 staging actual
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { printf 'Invalid pinned revision: %s\n' "$revision" >&2; return 1; }
  if [[ -d "$destination/.git" ]]; then
    check_existing_revision "$destination" "$revision"
    return
  fi
  [[ ! -e "$destination" && ! -L "$destination" ]] || {
    printf 'Existing directory needs review: %s\n' "$destination" >&2; return 1;
  }
  if declare -F progress_comm >/dev/null; then
    progress_comm "Installing $destination at $revision..."
  fi
  mkdir -p "$(dirname "$destination")"
  staging=$(mktemp -d "$(dirname "$destination")/.dogfiles-source-XXXXXX") || return
  # Fetch only the selected object and never check out a moving branch first.
  # Stage beside the destination so an interrupted/failed fetch is never used.
  if git init -q "$staging" &&
    git -C "$staging" remote add origin "$url" &&
    git -C "$staging" fetch --depth 1 origin "$revision" &&
    git -C "$staging" -c advice.detachedHead=false checkout --detach "$revision" &&
    actual=$(git -C "$staging" rev-parse HEAD) && [[ "$actual" == "$revision" ]]; then
    if ! mv "$staging" "$destination"; then
      rm -rf -- "$staging"
      return 1
    fi
  else
    rm -rf -- "$staging"
    printf 'Unable to install verified revision %s from %s\n' "$revision" "$url" >&2
    return 1
  fi
}
