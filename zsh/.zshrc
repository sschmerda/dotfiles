################################################################################
# zsh config
################################################################################

#################################################################################
# zsh + oh-my-zsh + powerlevel10k
################################################################################

# Prevent instant-prompt output issues in container shells.
if [[ -f /.dockerenv || -f /run/.containerenv ]]; then
  typeset -g POWERLEVEL9K_INSTANT_PROMPT=off
fi

# Enable Powerlevel10k instant prompt when the cached snippet exists.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Load oh-my-zsh only when it is installed.
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  # Load theme before loading oh-my-zsh.
  ZSH_THEME="powerlevel10k/powerlevel10k"
  # ZSH_THEME="robbyrussell"

  # Clone the following:
  # git clone https://github.com/zsh-users/zsh-autosuggestions.git $ZSH_CUSTOM/plugins/zsh-autosuggestions
  # git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
  plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
  )

  # Uncomment one of the following lines to change the auto-update behavior.
  zstyle ':omz:update' mode auto
  zstyle ':omz:update' frequency 1   # check every day

  # Uncomment the following line to enable command auto-correction.
  ENABLE_CORRECTION="true"

  # Uncomment the following line to display red dots whilst waiting for completion.
  COMPLETION_WAITING_DOTS="true"

  # Load Oh My Zsh.
  source "$ZSH/oh-my-zsh.sh"
fi

# Load Powerlevel10k config file.
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
if [[ -f ~/.p10k.zsh ]]; then
  source ~/.p10k.zsh
fi


################################################################################
# env variables
################################################################################

# Use Neovim as the default editor and man pager when it is available.
if command -v nvim >/dev/null 2>&1; then
  export EDITOR='nvim'
  export MANPAGER='nvim +Man!'
fi


################################################################################
# aliases
################################################################################
# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.

# lsd
if command -v lsd >/dev/null 2>&1; then
  alias ls="lsd"
  alias ll="lsd -lh"
  alias la="lsd -lAh"
  alias tree="lsd --tree"
fi

if command -v fzf >/dev/null 2>&1; then
  if command -v fd >/dev/null 2>&1; then
    _sd_fd_cmd='fd'
  elif command -v fdfind >/dev/null 2>&1; then
    _sd_fd_cmd='fdfind'
  fi

  if [[ -n "${_sd_fd_cmd:-}" ]]; then
    alias sd="cd && cd \$($_sd_fd_cmd --type d \
      --hidden \
      --exclude Documents \
      --exclude Library \
      --exclude Pictures \
      --exclude .Trash \
      --exclude .vscode \
      --exclude .SpaceVim \
      --exclude .cargo \
      --exclude .emacs \
      --exclude .emacs.d \
      --exclude .rstudio-desktop \
      --exclude .Rproj.user \
      --exclude .git \
      --exclude .cache \
      --exclude .local \
      | fzf)"
  fi
  unset _sd_fd_cmd
fi


################################################################################
# individual app config
################################################################################

# fzf
if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
fi

if [[ -f ~/.fzf.zsh ]]; then
  source ~/.fzf.zsh
fi


################################################################################
# individual config / app config based on operating system
################################################################################

if [[ "$OSTYPE" == darwin* ]] && [[ -f "$HOME/.config/zsh/macos.zsh" ]]; then
  source "$HOME/.config/zsh/macos.zsh"
elif [[ "$OSTYPE" == linux* ]] && [[ -f "$HOME/.config/zsh/linux.zsh" ]]; then
  source "$HOME/.config/zsh/linux.zsh"
fi


################################################################################
# individual config / app config based on containerization
################################################################################

if [[ -f /.dockerenv || -f /run/.containerenv ]]; then
  source "$HOME/.config/zsh/container.zsh"
fi


################################################################################
# individual config for local machine
################################################################################

if [[ -f "$HOME/.config/zsh/local.zsh" ]]; then
  source "$HOME/.config/zsh/local.zsh"
fi
