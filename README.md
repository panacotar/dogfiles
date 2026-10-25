## Omarchy desktop configuration

On Omarchy, use the separate installer below. The older `install.sh` described
later in this README targets Ubuntu/macOS and must not be used to set up Omarchy.
The existing root-level terminal files remain for that older setup; the Omarchy
terminal settings live under `omarchy/config/`.

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

## Toolset

- [oh-my-zsh](http://ohmyz.sh/)
- [git](https://git-scm.com/)
- Ruby via [`rbenv`](https://github.com/rbenv/rbenv)


### Change to nearby update servers
From the Software Sources app.

```
sudo apt update

sudo apt upgrade
```

```
sudo apt install -y curl git unzip vim zsh htop tree linux-headers-generic linux-headers-$(uname -r)
```

### ZSH

```
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

### Installation file
```
zsh install.sh

zsh git_setup.sh
```
```
exec zsh
```

### Ruby

The `install.sh` should've installed `rbenv`, check if installed with `rbenv -v`.   

Run this, which should take a while, around **10 mins**.
```
rbenv install 3.3.5
```
Set this as the global version:
```
rbenv global 3.3.5
```
```
exec zsh
```

Check if successful installed `ruby -v`

Update bundler:
```
gem update bundler
```
Install some gems:
```
gem install http pry-byebug rake rails:7.1.3.4 rspec sqlite3:1.7.3 activerecord:7.1.3.2 ruby-lsp
```

### Nodejs
```
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | zsh
```
```
exec zsh
```

Check if successful installed with `nvm -v`, then run:
```
nvm install 20.17.0
```
Check if successful installed `node -v`. Run:
```
nvm cache clear
```

### Install DBs
```
sudo apt install -y postgresql postgresql-contrib libpq-dev build-essential
```
Create role:
```
sudo -u postgres psql --command "CREATE ROLE \"`whoami`\" LOGIN createdb superuser;"
```
```
exec zsh
```

### Install tlp
It improves battery life:
```
sudo add-apt-repository ppa:linrunner/tlp

sudo apt-get install tlp tlp-rdw 
```

## Origin
This repository is based on [Le Wagon's](https://www.lewagon.com) dotfiles.
