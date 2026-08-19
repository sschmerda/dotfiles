-- Quarto supplies document commands and delegates executable chunks to the
-- shared REPL backend. Otter creates language-specific shadow buffers so LSP
-- completion and diagnostics work inside embedded Python/R/Julia chunks.
local function move_to_next_quarto_cell()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, row, -1, false)

  for offset, line in ipairs(lines) do
    if line:match("^%s*```%s*{") or line:match("^%s*~~~%s*{") then
      vim.api.nvim_win_set_cursor(0, { math.min(row + offset + 1, vim.api.nvim_buf_line_count(0)), 0 })
      return
    end
  end
end

return {
  {
    "quarto-dev/quarto-nvim",
    dependencies = {
      "jmbuhr/otter.nvim",
      "jpalardy/vim-slime",
      "nvim-treesitter/nvim-treesitter",
    },
    opts = {
      lspFeatures = {
        enabled = true,
        chunks = "curly",
        languages = nil,
        diagnostics = {
          enabled = true,
          triggers = { "BufWritePost" },
        },
        completion = {
          enabled = true,
        },
      },
      codeRunner = {
        enabled = true,
        default_method = function(cell, ignore_cols)
          require("config.repl").run_quarto_cell(cell, ignore_cols)
        end,
        never_run = { "yaml" },
      },
    },
    config = function(_, opts)
      local quarto = require("quarto")
      quarto.setup(opts)

      local group = vim.api.nvim_create_augroup("quarto_keymaps", { clear = true })
      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "quarto",
        callback = function(event)
          local runner = require("quarto.runner")
          local map_opts = { buffer = event.buf, silent = true }

          local has_which_key, which_key = pcall(require, "which-key")
          if has_which_key then
            which_key.add({
              { "<leader>R", group = "repl", icon = { icon = " ", color = "green" }, buffer = event.buf },
            })
          end

          vim.keymap.set("n", "<leader>Rc", runner.run_cell, vim.tbl_extend("force", map_opts, {
            desc = "Run current cell",
          }))
          vim.keymap.set("n", "<leader>Rn", function()
            runner.run_cell()
            move_to_next_quarto_cell()
          end, vim.tbl_extend("force", map_opts, {
            desc = "Run current cell and move next",
          }))
          vim.keymap.set("n", "<leader>Ra", runner.run_above, vim.tbl_extend("force", map_opts, {
            desc = "Run current cell and above",
          }))
          vim.keymap.set("n", "<leader>Rb", runner.run_below, vim.tbl_extend("force", map_opts, {
            desc = "Run current cell and below",
          }))
          vim.keymap.set("n", "<leader>RA", runner.run_all, vim.tbl_extend("force", map_opts, {
            desc = "Run all cells",
          }))
          vim.keymap.set("n", "<leader>Rl", runner.run_line, vim.tbl_extend("force", map_opts, {
            desc = "Run current line",
          }))
          vim.keymap.set("v", "<leader>Rs", runner.run_range, vim.tbl_extend("force", map_opts, {
            desc = "Run selected range",
          }))
        end,
      })
    end,
  },
}
