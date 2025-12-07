return {
  {
    "tzachar/local-highlight.nvim",
    config = function()
      require("local-highlight").setup({
        -- disable_file_types
        disable_file_types = { "tex" },
        hlgroup = "Search",
        cw_hlgroup = nil,
        -- Whether to display highlights in INSERT mode or not
        insert_mode = false,
      })
    end,
  },
}
