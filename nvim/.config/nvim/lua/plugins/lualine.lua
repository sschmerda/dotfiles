-- Surface the active shared REPL backend in the status line so <leader>R
-- actions are predictable when switching between Slime, Iron, and Molten.
return {
  {
    "nvim-lualine/lualine.nvim",
    optional = true,
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, 1, {
        function()
          return " " .. require("config.repl").backend()
        end,
        cond = function()
          return vim.bo.buftype == "" and vim.bo.filetype ~= ""
        end,
      })
    end,
  },
}
