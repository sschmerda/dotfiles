return {
  {
    "linux-cultist/venv-selector.nvim",
    dependencies = {
      "neovim/nvim-lspconfig",
      { "nvim-telescope/telescope.nvim", branch = "0.1.x", dependencies = { "nvim-lua/plenary.nvim" } }, -- optional: you can also use fzf-lua, snacks, mini-pick instead.
    },
    ft = "python", -- Load when opening Python files
    keys = {
      -- { ",v", "<cmd>VenvSelect<cr>" }, -- Open picker on keymap
    },
    opts = {
      notify_user_on_venv_activation = false,
      search = {
        anaconda_base = {
          command = "fd /python$ ${HOME}/anaconda3/bin --full-path --color never -E /proc",
          type = "anaconda",
        },
        anaconda_envs = {
          command = "fd /bin/python$ ${HOME}/anaconda3/envs --full-path --color never -E /proc",
          type = "anaconda",
        },
      },
      options = { activate_venv_in_terminal = true, set_environment_variables = true }, -- if you add plugin options, they go here.
    },
  },
}
