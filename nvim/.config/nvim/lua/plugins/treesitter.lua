return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = {
      "r", -- for R language
      "markdown", -- for Markdown
      "markdown_inline", -- enables inline markdown highlighting (optional but useful)
      "rnoweb",
      "yaml",
      "latex",
      "csv",
    },
    highlight = { enable = true },
  },
}
