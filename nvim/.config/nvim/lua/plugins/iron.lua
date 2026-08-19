-- Iron is the Neovim-managed terminal REPL backend. It opens a persistent
-- 40%-wide split on the right; config.repl adds contextual controls for it.
return {
  {
    "Vigemus/iron.nvim",
    config = function()
      local common = require("iron.fts.common")
      -- Prefer IPython for rich Python behavior but retain a plain-Python fallback.
      local python_command = vim.fn.executable("ipython") == 1 and { "ipython", "--no-autoindent" } or { "python3" }

      require("iron.core").setup({
        config = {
          scratch_repl = true,
          repl_definition = {
            python = {
              command = python_command,
              format = common.bracketed_paste_python,
              block_dividers = { "# %%", "#%%" },
              env = { PYTHON_BASIC_REPL = "1" },
            },
            r = { command = { "R" } },
            julia = { command = { "julia" } },
            bash = { command = { vim.o.shell } },
            sh = { command = { vim.o.shell } },
          },
          repl_open_cmd = require("iron.view").split.vertical.botright("40%"),
        },
        keymaps = {},
        ignore_blank_lines = true,
      })
    end,
  },
}
