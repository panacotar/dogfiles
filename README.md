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
