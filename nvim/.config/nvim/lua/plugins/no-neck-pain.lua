return {
  {
    "shortcuts/no-neck-pain.nvim",
    lazy = false,
    config = function()
      require("no-neck-pain").setup({ width = 120 })
      -- require("no-neck-pain").enable() -- Automatically enable at startup
      -- Re-enable no-neck-pain when entering a new file buffer
      vim.api.nvim_create_autocmd("BufEnter", {
        pattern = "*",
        callback = function()
          if vim.bo.filetype ~= "" then -- Ensure it's a file buffer
            require("no-neck-pain").enable()
          end
        end,
      })
    end,
    opts = {},
  },
}
