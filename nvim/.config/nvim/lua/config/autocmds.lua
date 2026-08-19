-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- Attach the shared REPL and Markdown key groups only to supported buffers.
-- Keeping setup here makes the mappings independent of plugin load order.
require("config.repl").setup()
require("config.markdown").setup()
