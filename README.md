## Set up a new machine

```bash
curl -fsSL https://raw.githubusercontent.com/panacotar/dogfiles/master/bootstrap.sh | bash
```

Preview without making changes:

```bash
curl -fsSL https://raw.githubusercontent.com/panacotar/dogfiles/master/bootstrap.sh | bash -s -- --dry-run
```

Run as your normal user in an interactive terminal. The URLs require the script on `master`.
Missing curl on Debian/Mint? Run first:

```bash
sudo apt-get update && sudo apt-get install -y curl ca-certificates
```

### What it sets up

- Supports macOS, Debian/Ubuntu/Linux Mint, and already-installed Omarchy.
- Clones to `~/code/darius/dogfiles`; preserves existing checkouts and local edits.
- Installs common tools: Git, curl, wget, unzip, Zsh, Vim, tldr, Lazygit, tmux, GPG, tig, tree, htop, SQLite, ExifTool, pkg-config, gh, and jq.
- On all supported platforms, installs Oh My Zsh and its plugins, then makes Zsh the login shell.
- Installs TPM and tmux plugins; links configs with backups and safe reruns.
- On Omarchy, applies desktop/terminal configs with personal `conf/` configs taking priority.

If macOS opens the command-line tools installer, finish it and rerun bootstrap.
Open a new terminal after setup. Options: `bash ~/code/darius/dogfiles/bootstrap.sh --help`.
Both installers share announcement formatting in `scripts/output.sh`; the
standalone bootstrap uses plain-text announcements until the checkout is available.

### Security and source updates

Zsh excludes relative directories from `PATH` and checks completion permissions.
Use `npm exec` or an explicit `./bin/COMMAND` for project tools. Alacritty allows
OSC52 clipboard writes, but blocks clipboard reads by terminal applications.

Code installed outside native package managers uses fixed commits in
`scripts/sources.sh` and `conf/tmux.conf`. The standalone bootstrap keeps its
Homebrew installer pin/checksum and Lazygit version/checksums near its package lists.
Oh My Zsh automatic updates are disabled; update pins deliberately after reviewing
upstream changes. Existing source checkouts and edits are preserved, with warnings
when their revisions differ. To adopt a new pin, move the old checkout aside and
rerun bootstrap (or select the corresponding optional installer task).
Install tmux plugins through bootstrap; TPM shortcuts do not resolve commit pins.
Homebrew/APT/Pacman continue to manage their own packages and updates.

### SSH and Git

Bootstrap skips SSH setup if `~/.ssh/github_id_ed25519` exists. Otherwise, it creates
the key and prints its public part. Register it in [GitHub SSH keys](https://github.com/settings/ssh/new)
as an authentication key, and as a signing key if using Git signing.

```bash
ssh -T git@github.com
```

To change the Git name and email stored in the shared config:

```bash
bash ~/code/darius/dogfiles/git_setup.sh
```

## Manage configs

Shared files live in `conf/`. Preview or reapply links, including after moving from the old root-level paths:

```bash
bash ~/code/darius/dogfiles/bootstrap.sh --configs-only --dry-run
bash ~/code/darius/dogfiles/bootstrap.sh --configs-only
```

- Keep the checkout in place: installed links point into it, and edits through them change the repo.
- Conflicts are backed up under `${XDG_STATE_HOME:-$HOME/.local/state}/dogfiles/backups/`. Restore a file by removing its link and moving its backup back.
- Tmux config is linked at both `~/.tmux.conf` and `${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf` so existing XDG settings cannot override it.
- Configs use `${XDG_CONFIG_HOME:-$HOME/.config}`; XDG paths must be absolute.
- Dry-run makes no changes. Without a checkout, file-level checks remain pending.

To add a config, place it under `conf/` and add a `source|root|destination` mapping:

```text
tmux.conf|home|.tmux.conf
```

`home` means `$HOME`; `config` means the XDG config directory. Both `common.links`
and `shell.links` apply on every supported platform; `macos.links` applies only on macOS.
Reapply links after updating a manifest.
Legacy Bash, PulseAudio, redshift, and launcher examples are saved but not automatically applied.

## Optional post-installation

```bash
bash ~/code/darius/dogfiles/install.sh
```

On macOS/Debian, choose runtimes, security tools, DBeaver, development apps, and desktop extras:

- Toggle numbered checkboxes with spaces or commas; `a` selects all. The menu updates in place.
- Press an empty Enter to install the current selection; `q` cancels.
- `n` clears all optional selections and continues immediately, without redrawing.
- Pick language versions afterward with rbenv, pyenv, or nvm.

Each `install.sh` run saves its output and errors in a unique
`logs/install-YYYYMMDD-HHMMSS-XXXXXX/output.log` under the checkout, while keeping
output visible in the terminal. Failures print `fix the reported issue and rerun.
Logged in ...` with the full path. Logs are private and gitignored; `--help` and
bootstrap dry-runs create none. Running `conf/macos` directly only prints to the
terminal; run it through `install.sh` to capture its output in the installation log.

**On macOS, continuing also applies all settings in [conf/macos](conf/macos), even with no optional packages selected.**
That file contains only your confirmed personal customizations: currently,
`ApplePressAndHoldEnabled=false` from the original installer. Add your own settings
there; inherited third-party defaults are excluded. To reapply it alone:

```bash
bash ~/code/darius/dogfiles/conf/macos
```

## Omarchy desktop

Bootstrap applies these settings automatically, skipping destinations managed by personal
`conf/` manifests so personal settings always win. For desktop configs only:

```bash
cd ~/code/darius/dogfiles
bash omarchy/install.sh --dry-run
bash omarchy/install.sh
hyprctl reload
hyprctl configerrors
```

- Add `--include-monitors` to restore monitor settings; they are skipped by default.
- Add new settings under `omarchy/config/` and list them in `omarchy/files.txt`.
- See the [restore guide](omarchy/RESTORE.md) for version requirements, themes, and undo steps.

## Development checks

```bash
python3 -m unittest discover -s tests -v
bash -n bootstrap.sh install.sh scripts/output.sh scripts/sources.sh conf/macos omarchy/install.sh
zsh -n conf/zshrc conf/aliases
```

Package installation is mocked; native Linux smoke checks remain manual.

Based on [Le Wagon's dotfiles](https://www.lewagon.com).
