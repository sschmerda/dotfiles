return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        copilot = {
          enabled = false,
        },
      },
    },
  },
  {
    "folke/sidekick.nvim",
    init = function()
      vim.g.sidekick_nes = false
    end,
    opts = {
      nes = {
        enabled = false,
      },
      cli = {
        mux = {
          enabled = false,
        },
        win = {
          layout = "float",
          float = {
            width = 0.5,
            height = 1,
            border = "rounded",
          },
        },
      },
    },
    keys = {
      {
        "<C-q>",
        function()
          require("sidekick.cli").hide()
        end,
        mode = "n",
        desc = "Hide Sidekick CLI",
      },
      {
        "<C-q>",
        [[<C-\><C-n><cmd>lua require("sidekick.cli").hide()<cr>]],
        mode = "t",
        desc = "Hide Sidekick CLI",
      },
    },
  },
}
