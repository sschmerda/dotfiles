-- print a line at 80 and 120 characters
return {
  {
    "lukas-reineke/virt-column.nvim",
    opts = {
      char = "│", -- the vertical line character
      virtcolumn = "80,120", -- column position
    },
  },
}
