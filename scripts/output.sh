#!/usr/bin/env bash
# Shared announcements for the bootstrap and optional post-installer.
# Source this file, then call init_output [auto|true|false] to configure colors.

init_output() {
  local color_mode=${1:-auto}
  BOLD= NORMAL= GREEN=
  if [[ "$color_mode" == true || ( "$color_mode" == auto && -t 1 ) ]] &&
    [[ ${TERM:-dumb} != dumb ]] && command -v tput >/dev/null 2>&1; then
    BOLD=$(tput bold 2>/dev/null || true)
    NORMAL=$(tput sgr0 2>/dev/null || true)
    GREEN=$(tput setaf 2 2>/dev/null || true)
  fi
}

trumpet() {
  printf '\n%s#################################\n %s \n#################################%s\n' "$GREEN" "$1" "$NORMAL"
}

progress_comm() { printf '\n-----> %s\n' "$1"; }
