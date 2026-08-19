-- Slime is the lightweight external-REPL backend. It sends text to a tmux
-- target (normally an IPython/R/Julia pane); config.repl supplies all mappings.
return {
  {
    "jpalardy/vim-slime",
    init = function()
      vim.g.slime_target = "tmux"
      vim.g.slime_python_ipython = 1
      -- Disable Slime defaults, including Ctrl-C Ctrl-C, in favor of <leader>R.
      vim.g.slime_no_mappings = 1
    end,
  },
}
