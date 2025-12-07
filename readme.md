# Readme

## General

Dotfiles are are being managed by `gnu stow`

Single config:

```bash
stow -t ~ nvim
```

All confgs:

```bash
stow -t ~ .
```

## Programs to install

### General

#### Shell

> [!WARNING]
> Create a shell script which install all dependencies. Use brew and apt

- zsh + oh-my-zsh + powerline10k + oh-my-zsh plugins
- git
- lazyvim
- gnu stow
- lsd
- fd
- nerd fonts (hack nerd font mono)
- conda
- quarto
- btop/htop
- lazygit
- lazydocker
- yazi
- curl
- (maybe zoxide)
- latex

##### neovim

- to install lazyvim follow the [instructions](https://www.lazyvim.org/)

##### fzf

- use command line commands

##### tmux

- ```shell
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

  ```

- `Ctrl+I` within tmux
- it could be that session x requires a newer bash version, which should be installed via homebrew

#### Gui

- vscode
- zotero
- obsidian
- ghostty

### MACOS

- brew
- tiling window manager
