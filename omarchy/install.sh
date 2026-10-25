#!/usr/bin/env bash
# Install only the reviewed files listed in files.txt; no packages or theme changes.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: bash omarchy/install.sh [--dry-run] [--include-monitors]

Link Omarchy settings into ${XDG_CONFIG_HOME:-$HOME/.config}.
Existing files and conflicting links are preserved in a unique directory under
${XDG_STATE_HOME:-$HOME/.local/state}/dogfiles/backups/.
Monitor settings are skipped unless --include-monitors is supplied.
--dry-run prints changes without creating directories, backups, or links.
HELP
}

dry_run=false
include_monitors=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    --include-monitors) include_monitors=true ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
config_root=${XDG_CONFIG_HOME:-$HOME/.config}
state_root=${XDG_STATE_HOME:-$HOME/.local/state}
# Absolute XDG paths are required by the XDG specification.
if [[ "$config_root" != /* || "$state_root" != /* ]]; then
  printf 'Configuration and state paths must be absolute.\n' >&2
  exit 1
fi

files=()
while IFS= read -r relative || [[ -n "$relative" ]]; do
  [[ -z "$relative" || "$relative" == \#* ]] && continue
  if [[ "$relative" == /* || "/$relative/" == */../* || "$relative" != */* ]]; then
    printf 'Invalid manifest path: %s\n' "$relative" >&2
    exit 1
  fi
  if [[ "$relative" == hypr/monitors.lua && "$include_monitors" == false ]]; then
    printf 'Skip monitor settings (use --include-monitors).\n'
    continue
  fi
  source_file="$script_dir/config/$relative"
  target_file="$config_root/$relative"
  if [[ ! -f "$source_file" || -L "$source_file" ]]; then
    printf 'Missing regular source file: %s\n' "$source_file" >&2
    exit 1
  fi
  if [[ -d "$target_file" && ! -L "$target_file" ]]; then
    printf 'Expected a file, found a directory: %s\n' "$target_file" >&2
    exit 1
  fi
  # Refuse a conflicting parent file before making any changes.
  parent=$(dirname -- "$target_file")
  while [[ "$parent" != / ]]; do
    if [[ ( -e "$parent" || -L "$parent" ) && ! -d "$parent" ]]; then
      printf 'Parent is not a directory: %s\n' "$parent" >&2
      exit 1
    fi
    parent=$(dirname -- "$parent")
  done
  files+=("$relative")
done < "$script_dir/files.txt"

backup_dir=
for relative in "${files[@]}"; do
  source_file="$script_dir/config/$relative"
  target_file="$config_root/$relative"
  if [[ -L "$target_file" && "$(readlink -- "$target_file")" == "$source_file" ]]; then
    printf 'Already linked: %s\n' "$target_file"
    continue
  fi
  if [[ -e "$target_file" || -L "$target_file" ]]; then
    if "$dry_run"; then
      printf 'Would back up: %s\n' "$target_file"
    else
      if [[ -z "$backup_dir" ]]; then
        backup_root="$state_root/dogfiles/backups"
        mkdir -p -- "$backup_root"
        backup_dir=$(mktemp -d "$backup_root/omarchy-$(date +%Y%m%d-%H%M%S)-XXXXXX")
      fi
      mkdir -p -- "$(dirname -- "$backup_dir/$relative")"
      mv -- "$target_file" "$backup_dir/$relative"
      printf 'Backed up: %s -> %s\n' "$target_file" "$backup_dir/$relative"
    fi
  fi
  if "$dry_run"; then
    printf 'Would link: %s -> %s\n' "$target_file" "$source_file"
  else
    mkdir -p -- "$(dirname -- "$target_file")"
    ln -s -- "$source_file" "$target_file"
    printf 'Linked: %s -> %s\n' "$target_file" "$source_file"
  fi
done
if [[ -n "$backup_dir" ]]; then
  printf '\nOriginal files saved in: %s\n' "$backup_dir"
fi
printf '\nNo services reloaded. After installation, run hyprctl reload and hyprctl configerrors.\n'
printf 'Open a new terminal window or reload your terminal to apply its settings.\n'
