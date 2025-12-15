################################################################################
# zsh config
################################################################################

#################################################################################
# zsh + oh-my-zsh + powerlevel10k
################################################################################

# Enable Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Path to your oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Load theme before loading oh-my-zsh
ZSH_THEME="powerlevel10k/powerlevel10k"
# ZSH_THEME="robbyrussell"


# clone the following:
# git clone https://github.com/zsh-users/zsh-autosuggestions.git $ZSH_CUSTOM/plugins/zsh-autosuggestions
# git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
)

# Load Oh My Zsh
source $ZSH/oh-my-zsh.sh

# Load Powerlevel10k config file
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Uncomment one of the following lines to change the auto-update behavior
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 1   # check every day

# Uncomment the following line to enable command auto-correction.
ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"


################################################################################
# User configuration
################################################################################

# You may need to manually set your language environment
export LANG=en_US.UTF-8

################################################################################
# aliases
################################################################################
# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.


# lsd
alias ls="lsd"
alias ll="lsd -lh"
alias la="lsd -lAh"
alias tree="lsd --tree"

# fzf powered directory change using fd
alias sd='cd && cd $(fd --type d\
                        --hidden\
                        --exclude Documents\
                        --exclude Library\
                        --exclude Pictures\
                        --exclude .Trash\
                        --exclude .vscode\
                        --exclude .SpaceVim\
                        --exclude .cargo\
                        --exclude .emacs\
                        --exclude .emacs.d\
                        --exclude .rstudio-desktop\
                        --exclude .Rproj.user\
                        --exclude .git\
                        --exclude .cache\
                        --exclude .local\
                     | fzf)'


################################################################################
# env variables
################################################################################


# default editor
export EDITOR='nvim'

# export
export MANPAGER='nvim +Man!'


################################################################################
# individual app config
################################################################################


# anaconda
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$("$HOME/anaconda3/bin/conda" "shell.zsh" "hook" 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# fzf
source <(fzf --zsh)
export PATH="$PATH:$HOME/.local/bin"
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# quarto
# quarto env variable
export QUARTO_PYTHON=$(which jupyter)


################################################################################
# individual app config based on operating system
################################################################################

if [[ "$OSTYPE" == darwin* ]] && [[ -f "$HOME/.config/zsh/macos.zsh" ]]; then
    source "$HOME/.config/zsh/macos.zsh"
elif [[ "$OSTYPE" == linux* ]] && [[ -f "$HOME/.config/zsh/linux.zsh" ]]; then
    source "$HOME/.config/zsh/linux.zsh"
fi
