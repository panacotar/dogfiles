ZSH=$HOME/.oh-my-zsh

# You can change the theme with another one from https://github.com/robbyrussell/oh-my-zsh/wiki/themes
# "murilasso"
# ZSH_THEME="frisk"
ZSH_THEME="robbyrussell"
# ZSH_THEME="awesomepanda"

# Useful oh-my-zsh plugins
plugins=(git gitfast last-working-dir common-aliases history-substring-search ssh-agent colored-man-pages zsh-autosuggestions)

# Prevent adding to history commands which are prefixed by a space
setopt HIST_IGNORE_SPACE

# (macOS-only) Prevent Homebrew from reporting - https://github.com/Homebrew/brew/blob/master/share/doc/homebrew/Analytics.md
export HOMEBREW_NO_ANALYTICS=1
ZSH_DISABLE_COMPFIX=true

# Actually load Oh-My-Zsh
source "${ZSH}/oh-my-zsh.sh"
unalias rm # No interactive rm by default (brought by plugins/common-aliases)
source "${HOME}/.custom_commands.sh"

# Load rbenv if installed (To manage your Ruby versions)
export PATH="${HOME}/.rbenv/bin:${PATH}" # Needed for Linux/WSL
type -a rbenv > /dev/null && eval "$(rbenv init -)"

# Load pyenv (To manage your Python versions)
export PATH="${HOME}/.pyenv/bin:${PATH}" # Needed for Linux/WSL
type -a pyenv > /dev/null && eval "$(pyenv init -)" && eval "$(pyenv virtualenv-init -)"

# Load nvm if installed (To manage your Node versions)
export NVM_DIR="$HOME/.nvm"
[ -s "/usr/local/opt/nvm/nvm.sh" ] && . "/usr/local/opt/nvm/nvm.sh"

# Rails and Ruby uses the local `bin` folder to store binstubs.
# So instead of running `bin/rails` like the doc says, just run `rails`
# Same for `./node_modules/.bin` and nodejs
export PATH="./bin:./node_modules/.bin:${PATH}:/usr/local/sbin"

# Store your own aliases in the ~/.aliases file and load the here.
[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"

# Encoding stuff for the terminal
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Key bindings

# Load NVM (managing the node versions)
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
export PATH="$HOME/.rbenv/bin:$PATH"
export PATH=/usr/local/mysql/bin:$PATH
eval "$(rbenv init -)"

export BUNDLER_EDITOR=code
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$PATH 
# New Go installation
export PATH=$PATH:/usr/local/go/bin

export EDITOR='vim'
# export ZELLIJ_CONFIG_DIR=$HOME/.config/zellij-me

export PATH=/opt/homebrew/bin:$PATH
export PATH=/opt/homebrew/Cellar/openvpn/2.6.5/sbin/:$PATH # This adds openvpn to path
