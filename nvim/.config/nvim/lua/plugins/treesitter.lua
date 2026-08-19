-- Parsers required by Quarto/Otter language injection, contextual snippets,
-- Markdown rendering, and cell detection across the supported REPL languages.
return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = {
      "bash",
      "julia",
      "python",
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
