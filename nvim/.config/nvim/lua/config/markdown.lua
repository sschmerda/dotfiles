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

-- quarto-nvim starts previews in a temporary tab so their terminal output is
-- retained. Keep that buffer loaded and searchable, but close its window so a
-- background preview does not force Neovim's tabline to appear.
local function hide_quarto_preview_terminal(source_buf)
  local ok, output_buf = pcall(vim.api.nvim_buf_get_var, source_buf, "quartoOutputBuf")
  if not ok or not vim.api.nvim_buf_is_valid(output_buf) then
    return
  end

  vim.bo[output_buf].bufhidden = "hide"
  vim.bo[output_buf].buflisted = true

  for _, win in ipairs(vim.fn.win_findbuf(output_buf)) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

-- Quarto cannot open the host browser from inside the devcontainer. Bind the
-- preview server to the forwarded port instead and show the host URL to open.
-- Requiring both signals avoids changing preview behavior in unrelated Docker
-- containers or on hosts that happen to define QUARTO_PORT.
local function quarto_preview()
  local source_buf = vim.api.nvim_get_current_buf()
  local in_devcontainer = vim.fn.filereadable("/.dockerenv") == 1
    and vim.env.QUARTO_PORT ~= nil
    and vim.env.QUARTO_PORT ~= ""

  if not in_devcontainer then
    require("quarto").quartoPreview()
    hide_quarto_preview_terminal(source_buf)
    return
  end

  local port = tonumber(vim.env.QUARTO_PORT) or 4200
  if port < 1 or port > 65535 or port % 1 ~= 0 then
    port = 4200
  end

  require("quarto").quartoPreview({
    args = string.format("--host 0.0.0.0 --port %d --no-browser", port),
  })
  hide_quarto_preview_terminal(source_buf)

  vim.schedule(function()
    vim.notify(
      string.format("Open this address in the host browser:\nhttp://localhost:%d", port),
      vim.log.levels.INFO,
      { title = "Quarto preview", timeout = 10000 }
    )
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
    map(buf, "<leader>Mp", quarto_preview, "Quarto preview")
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
