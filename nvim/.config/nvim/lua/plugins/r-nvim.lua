return {
  {
    "R-nvim/R.nvim",
    -- Only required if you also set defaults.lazy = true
    lazy = false,
    init = function()
      -- Quarto chunks are handled contextually through Otter. Keeping Quarto
      -- out of this list prevents R.nvim from attaching to Python-only files.
      vim.g.R_filetypes = { "r", "rmd", "rnoweb", "rhelp" }
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- R.nvim already provides r_ls, so avoid starting a second R server.
        r_language_server = {
          enabled = false,
        },
      },
    },
  },
}
