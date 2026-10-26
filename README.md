## Set up a new machine

```bash
curl -fsSL https://raw.githubusercontent.com/panacotar/dogfiles/master/bootstrap.sh | bash
```

Preview first, without making changes:

```bash
curl -fsSL https://raw.githubusercontent.com/panacotar/dogfiles/master/bootstrap.sh | bash -s -- --dry-run
```

These commands work once `bootstrap.sh` is published on `master`. Run as your normal
user in an interactive terminal. The initial download requires curl; on a minimal
Debian/Mint installation, install it first with `sudo apt-get update` and
`sudo apt-get install -y curl ca-certificates`. macOS includes curl. Terminal input
for passphrases and administrator authentication is read from `/dev/tty`, so the
piped command can still prompt.

The bootstrap supports macOS, Debian/Ubuntu/Linux Mint, and already-installed
Omarchy. It installs missing prerequisites, creates `~/code/darius` if necessary,
and clones this repository into `~/code/darius/dogfiles`. New clones use HTTPS for
the download and SSH for their origin afterward. Existing checkouts, branches,
remotes, and uncommitted edits are preserved; other repositories at that path are
rejected. Keep the checkout in place because the installed configs link into it.

On macOS, missing Apple command-line tools may open an installation dialog.
Complete that installation and rerun the bootstrap. Homebrew is installed if
needed. Debian-family systems use APT; Omarchy uses its existing Pacman database.
If Pacman reports stale packages, update through Omarchy and rerun; bootstrap does
not independently refresh the database or perform a system upgrade.

### Common CLI tools

Git, curl, wget, unzip, Zsh, Vim, tldr, Lazygit, tmux, GPG, tig, tree, htop, SQLite,
ExifTool, pkg-config, GitHub CLI (`gh`), and jq. Package names vary by platform;
tealdeer supplies `tldr` unless a working client already exists. On Debian/Mint,
Lazygit uses APT when available, otherwise a checksum-verified upstream binary for
x86_64 or ARM64. X11 Debian/Mint sessions also receive xclip.

On macOS and Debian/Mint, bootstrap installs Oh My Zsh, autosuggestions, syntax
highlighting, TPM and the configured tmux plugins, then changes the login shell to
Zsh after validating its config. Optional runtimes are not required for startup.
Open a new terminal afterward. If `chsh` is blocked, follow the printed command.

### SSH and GitHub

If `~/.ssh/github_id_ed25519` already exists, the entire SSH setup stage is skipped.
Otherwise the bootstrap creates a new Ed25519 key with a passphrase prompt,
configures its GitHub identity, loads it into an agent (using Keychain on macOS),
and prints the public key. Add it manually under
[GitHub SSH keys](https://github.com/settings/ssh/new), then test:

```bash
ssh -T git@github.com
```

GitHub prints a successful authentication message but returns status 1 because it
does not provide shell access. If using the SSH signing settings in `conf/gitconfig`,
also register the public key as a signing key. Never commit private keys or credentials.
If setup skipped an existing key, its SSH config and agent loading remain yours to manage.

### Configs, reruns, and backups

Shared assets live in `conf/`; `*.links` manifests map reviewed files into your home
and `${XDG_CONFIG_HOME:-$HOME/.config}`. Omarchy retains its own manifest and installer.
Config directories must use absolute XDG paths. Existing conflicting files and
links are backed up under `${XDG_STATE_HOME:-$HOME/.local/state}/dogfiles/backups/`
in a unique directory, preserving their full destination paths. Correct links are
left alone. To undo a link, remove it and restore the original from its printed
backup location. Config sources are not copied: edits through installed links
change the checkout.

From an existing checkout, preview or apply configuration links without package,
SSH, repository, plugin, or login-shell setup:

```bash
bash ~/code/darius/dogfiles/bootstrap.sh --configs-only --dry-run
bash ~/code/darius/dogfiles/bootstrap.sh --configs-only
```

Use this when migrating installed links from the former root-level config paths.
`--configs-only` uses the script’s own checkout when invoked from a local file.
The historical Alacritty config path is linked alongside its current XDG path.
Legacy Bash, PulseAudio, redshift, and desktop launcher examples are retained under
`conf/` but are not automatically applied. The macOS preferences script is linked
as `~/.macos`, without being executed.

Dry-run prints platform/packages, SSH work, checkout actions, config links/backups,
plugins and login-shell changes. It does not run sudo, install anything, write
logs, create directories, clone repositories, generate keys, start agents, or
change files or the shell. Without a local checkout, it describes the config stage
and marks file-level checks as pending. Once a checkout is present, it checks the
actual manifests, sources and destination conflicts. It forwards dry-run to the
Omarchy config installer too.

### Optional post-installation

Run the separate second stage whenever you want its extras:

```bash
bash ~/code/darius/dogfiles/install.sh
```

It prompts for Ruby tooling (rbenv/ruby-build), Go, Python tooling
(pyenv/pyenv-virtualenv), Node tooling (nvm), security tools, DBeaver, Zellij, and
platform-specific development apps, services, and desktop/hardware settings.
Each choice defaults to no. It does not reinstall common packages, install Oh My
Zsh, or relink shared configs. It works from any working directory on macOS and
Debian/Mint; Omarchy uses its own package/application management.

Choose language versions per project after installing managers, for example
`rbenv install VERSION`, `pyenv install VERSION`, or `nvm install --lts` in a new
terminal. Git identity can be adjusted with `bash ~/code/darius/dogfiles/git_setup.sh`.

## Omarchy desktop configuration

The bootstrap detects an existing Omarchy installation, installs common CLI tools,
links shared Git/Vim/tmux settings, and invokes `omarchy/install.sh`. It preserves
Omarchy’s shell and terminal integration; Oh My Zsh and the shared Zsh config are
only installed on macOS and Debian/Mint. Install Omarchy itself first.

For desktop configuration only, use the separate installer below. The optional
root `install.sh` targets macOS/Debian/Mint and must not be used on Omarchy.
Terminal and desktop settings remain under `omarchy/config/`.

1. Install Omarchy and your required applications, including
   `openai-codex-desktop` for the Super + Shift + A shortcut.
2. Clone this repository, then review and install its desktop settings:

   ```bash
   git clone https://github.com/panacotar/dogfiles.git ~/code/darius/dogfiles
   cd ~/code/darius/dogfiles
   bash omarchy/install.sh --dry-run
   bash omarchy/install.sh
   ```

   The installer works from any working directory. It links individual files,
   preserves existing files and conflicting links under
   `${XDG_STATE_HOME:-$HOME/.local/state}/dogfiles/backups/`, and leaves correct
   links untouched when run again. `XDG_CONFIG_HOME` is respected when set.
   Keep the cloned repository in place: moving or deleting it breaks the links.
3. Review [the captured environment and theme instructions](omarchy/RESTORE.md).
   Apply the theme manually. Monitor settings are skipped by default; to restore
   them too, review `omarchy/config/hypr/monitors.lua`, then run:

   ```bash
   bash omarchy/install.sh --include-monitors --dry-run
   bash omarchy/install.sh --include-monitors
   ```

4. Apply and validate Hyprland settings:

   ```bash
   hyprctl reload
   hyprctl configerrors
   ```

   Open a new terminal window or reload your terminal to apply terminal settings.
5. Edit your settings normally, then review, commit, and push from this repository:

   ```bash
   git status --short
   git diff -- omarchy
   git add -- omarchy README.md
   git diff --cached
   git commit -m "Update Omarchy configuration"
   git push
   ```

Only reviewed paths in `omarchy/files.txt` are installed. To version another
setting, review it for secrets, add its file under `omarchy/config/`, add its
relative path to that manifest, and rerun the installer. Do not add caches,
credentials, generated themes, or backup files. The installer does not install
packages, apply themes, reload services, commit, or push.

## Development checks

```bash
python3 -m unittest discover -s tests -v
bash -n bootstrap.sh install.sh zellij/install_zellij.sh omarchy/install.sh
zsh -n conf/zshrc conf/aliases
```

The tests use isolated homes and mocked system commands; they do not install
packages or change the developer’s login shell. Real Linux/Pacman package
installation still needs a smoke test on the target machine.

## Origin

This repository is based on [Le Wagon's](https://www.lewagon.com) dotfiles.
