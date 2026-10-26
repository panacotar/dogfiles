#!/usr/bin/env bash
# Optional binary installer, invoked by the post-installation script.
set -euo pipefail
if command -v zellij >/dev/null 2>&1; then echo 'Zellij is already installed.'; exit 0; fi
case "$(uname -m)" in
  x86_64|amd64) arch=x86_64 ;;
  aarch64|arm64) arch=aarch64 ;;
  *) echo 'Unsupported Zellij architecture.' >&2; exit 1 ;;
esac
case "$(uname -s)" in
  Darwin) target=apple-darwin ;;
  Linux) target=unknown-linux-musl ;;
  *) echo 'Unsupported Zellij platform.' >&2; exit 1 ;;
esac
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dogfiles-zellij.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
curl -fsSL "https://github.com/zellij-org/zellij/releases/latest/download/zellij-$arch-$target.tar.gz" -o "$tmp_dir/zellij.tar.gz"
tar -xzf "$tmp_dir/zellij.tar.gz" -C "$tmp_dir" zellij
sudo -v </dev/tty
sudo install -m 0755 "$tmp_dir/zellij" /usr/local/bin/zellij
zellij --version
