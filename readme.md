# Readme

## General

Dotfiles are are being managed by `gnu stow`

Single config:

```bash
stow -t ~ nvim
```

All confgs:

```bash
stow -t ~ */
```

## Zsh Config Layout

The shared zsh config is split by scope:

- `zsh/.zshrc`
  - portable base config
  - guards optional tools like `nvim`, `lsd`, `fd`, `fzf`, and `oh-my-zsh`
- `zsh/.config/zsh/macos.zsh`
  - macOS-specific config
  - contains host OS settings such as `LANG` and macOS-only PATH additions
- `zsh/.config/zsh/linux.zsh`
  - Linux-specific config
  - contains Debian/Ubuntu command remaps such as `fd -> fdfind` and `bat -> batcat`
- `zsh/.config/zsh/container.zsh`
  - container-only config
  - contains container session fallbacks such as the `TERM` default
- `zsh/.config/zsh/local.zsh`
  - machine-local config
  - sourced last
  - intended for host-specific settings that should not live in the shared dotfiles repo
  - ignored by Git
- `zsh/.config/zsh/local.zsh.example`
  - template for the local machine-specific file

Use `local.zsh` for machine-specific shell integration such as local Anaconda setup or one-off PATH additions. Keep shared `.zshrc` portable and free of hardcoded host-specific runtime state.

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
