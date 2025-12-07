return {
  -- -- add gruvbox
  { "ellisonleao/gruvbox.nvim", name = "gruvbox" },
  --
  { "yeddaif/neovim-purple", name = "neovim-purple" },
  --
  { "Rigellute/shades-of-purple.vim" },
  --
  { "rose-pine/neovim", name = "rose-pine" },
  --
  -- -- Configure LazyVim to load gruvbox
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
