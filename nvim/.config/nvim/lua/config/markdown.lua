-- Contextual <leader>M workflow for Markdown-like files and Jupytext Python.
-- Markdown and Quarto receive rendering/preview commands; Python receives
-- only notebook-cell snippets so the group stays useful outside prose files.
local M = {}

local supported_filetypes = {
  markdown = true,
  ["markdown.mdx"] = true,
  quarto = true,
  python = true,
}

local markdown_filetypes = {
  markdown = true,
  ["markdown.mdx"] = true,
  quarto = true,
}

local function map(buf, lhs, rhs, desc)
  vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc })
end

local function add_group(buf)
  local ok, which_key = pcall(require, "which-key")
  if ok then
    which_key.add({
      {
        "<leader>M",
        group = "markdown / notebook",
        icon = { icon = "󰠮 ", color = "blue" },
        buffer = buf,
      },
    })
  end
end

local function browse_snippets(buf)
  local ok, blink = pcall(require, "blink.cmp")
  if not ok then
    vim.notify("Blink completion is unavailable", vim.log.levels.ERROR)
    return
  end

  if vim.bo[buf].filetype == "python" then
    vim.b[buf].jupytext_snippets_only = true
    vim.api.nvim_create_autocmd("User", {
      pattern = "BlinkCmpMenuClose",
      once = true,
      callback = function()
        if vim.api.nvim_buf_is_valid(buf) then
          vim.b[buf].jupytext_snippets_only = nil
        end
      end,
    })
  end

  vim.cmd.startinsert()
  vim.schedule(function()
    blink.show({ providers = { "snippets" } })
  end)
end

local function attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local filetype = vim.bo[buf].filetype
  if not supported_filetypes[filetype] then
    return
  end

  add_group(buf)
  map(buf, "<leader>Ms", function()
    browse_snippets(buf)
  end, filetype == "python" and "Browse Jupytext snippets" or "Browse snippets")

  if markdown_filetypes[filetype] then
    map(buf, "<leader>Mr", function()
      require("render-markdown").toggle()
    end, "Toggle rendered Markdown")
  end

  if filetype == "quarto" then
    map(buf, "<leader>Mp", function()
      require("quarto").quartoPreview()
    end, "Quarto preview")
    map(buf, "<leader>Mc", "<cmd>QuartoClosePreview<cr>", "Close Quarto preview")
  elseif filetype == "markdown" or filetype == "markdown.mdx" then
    map(buf, "<leader>Mp", "<cmd>MarkdownPreviewToggle<cr>", "Markdown preview")
    map(buf, "<leader>Mc", "<cmd>MarkdownPreviewStop<cr>", "Close Markdown preview")
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("markdown_notebook_keymaps", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = vim.tbl_keys(supported_filetypes),
    callback = function(event)
      attach(event.buf)
    end,
  })

  vim.schedule(function()
    attach(vim.api.nvim_get_current_buf())
  end)
end

return M
