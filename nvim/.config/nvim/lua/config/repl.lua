-- Shared REPL workflow for ordinary source files and Quarto code chunks.
-- This module owns the buffer-local <leader>R mappings, cell detection, and
-- backend selection; plugin files only configure Slime, Iron, and Molten.
-- A buffer may override vim.g.repl_backend through vim.b.repl_backend.
local M = {}

local cell_delimiters = {
  bash = [[^#\s*%%]],
  julia = [[^#\s*%%]],
  lua = [[^--\s*%%]],
  python = [[^#\s*%%]],
  r = [[^#\s*\%(%%\|----\)]],
  sh = [[^#\s*%%]],
  sql = [[^--\s*%%]],
  zsh = [[^#\s*%%]],
}

local backends = { "slime", "iron", "molten" }
local backend_control_keys = { "<leader>Rf", "<leader>Rh", "<leader>Ri", "<leader>Rr", "<leader>Rt" }

function M.backend()
  return vim.b.repl_backend or vim.g.repl_backend or "slime"
end

local function backend_available(backend)
  if backend == "slime" then
    return vim.fn.exists(":SlimeSend") == 2
  elseif backend == "iron" then
    return pcall(require, "iron.core")
  elseif backend == "molten" then
    return vim.fn.exists(":MoltenInit") == 2
  end

  return false
end

local function require_backend()
  local backend = M.backend()
  if backend_available(backend) then
    return backend
  end

  vim.notify("REPL backend '" .. backend .. "' is unavailable", vim.log.levels.ERROR)
end

local function buffer_map(buf, lhs, rhs, desc)
  vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc })
end

local function clear_backend_controls(buf)
  for _, lhs in ipairs(backend_control_keys) do
    pcall(vim.keymap.del, "n", lhs, { buffer = buf })
  end
end

local function iron_filetype(buf)
  local filetype = vim.bo[buf].filetype
  if filetype ~= "quarto" then
    return filetype
  end

  local ok, keeper = pcall(require, "otter.keeper")
  local language = ok and keeper.get_current_language_context(buf) or nil
  language = language or vim.b[buf].iron_repl_filetype
  if not language then
    vim.notify("Place the cursor in a Quarto code chunk before using Iron", vim.log.levels.WARN)
    return
  end

  vim.b[buf].iron_repl_filetype = language
  return language
end

local function focus_iron_repl(buf)
  local filetype = iron_filetype(buf)
  if filetype then
    require("iron.core").focus_on(filetype)
  end
end

local function hide_iron_repl(buf)
  local filetype = iron_filetype(buf)
  if filetype then
    require("iron.core").hide_repl(filetype)
  end
end

local function restart_iron_repl(buf)
  local filetype = iron_filetype(buf)
  if not filetype then
    return
  end

  local source_window = vim.api.nvim_get_current_win()
  local iron = require("iron.core")
  iron.focus_on(filetype)
  iron.repl_restart()
  if vim.api.nvim_win_is_valid(source_window) then
    vim.api.nvim_set_current_win(source_window)
  end
end

-- Backend-specific controls reuse the same keys and are rebuilt whenever the
-- selected backend changes, preventing stale Iron or Molten actions.
local function sync_backend_controls(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  clear_backend_controls(buf)
  local backend = vim.b[buf].repl_backend or vim.g.repl_backend or "slime"
  if backend == "slime" then
    buffer_map(buf, "<leader>Rt", "<cmd>SlimeConfig<cr>", "Configure Slime target")
  elseif backend == "iron" then
    buffer_map(buf, "<leader>Rt", function()
      require("config.repl").configure_backend()
    end, "Open Iron REPL")
    buffer_map(buf, "<leader>Rf", function()
      focus_iron_repl(buf)
    end, "Focus Iron REPL")
    buffer_map(buf, "<leader>Rh", function()
      hide_iron_repl(buf)
    end, "Hide Iron REPL")
    buffer_map(buf, "<leader>Rr", function()
      restart_iron_repl(buf)
    end, "Restart Iron REPL")
  else
    buffer_map(buf, "<leader>Rt", "<cmd>MoltenInit<cr>", "Initialize Molten kernel")
    if vim.b[buf].molten_active then
      buffer_map(buf, "<leader>Rr", "<cmd>MoltenRestart<cr>", "Restart Molten kernel")
    end
  end

  if vim.b[buf].molten_active then
    buffer_map(buf, "<leader>Ri", "<cmd>MoltenInterrupt<cr>", "Interrupt Molten kernel")
  end
end

-- Molten display settings are buffer-local session overrides. The configured
-- globals remain the restart defaults and are never rewritten by prompts.
local function molten_default_output_lines()
  return tonumber(vim.g.molten_virt_text_max_lines) or 40
end

local function molten_output_lines(buf)
  return tonumber(vim.b[buf].molten_virt_text_max_lines) or molten_default_output_lines()
end

-- Molten exposes this as a runtime-wide option, so reapply each buffer's
-- session-local override whenever that initialized buffer becomes active.
local function apply_molten_output_lines(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.b[buf].molten_active then
    return
  end

  local ok, err = pcall(vim.fn.MoltenUpdateOption, "virt_text_max_lines", molten_output_lines(buf))
  if not ok then
    vim.notify("Could not update Molten output lines: " .. tostring(err), vim.log.levels.ERROR)
  end
end

local function set_molten_output_lines(buf)
  local current = molten_output_lines(buf)
  vim.ui.input({
    prompt = "Molten maximum output lines: ",
    default = tostring(current),
  }, function(input)
    if input == nil then
      return
    end

    local value = tonumber(input)
    if not value or value < 1 or value % 1 ~= 0 then
      vim.notify("Molten output lines must be a positive integer", vim.log.levels.ERROR)
      return
    end

    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    vim.b[buf].molten_virt_text_max_lines = value
    if vim.api.nvim_get_current_buf() ~= buf or not vim.b[buf].molten_active then
      return
    end

    local ok, err = pcall(vim.fn.MoltenUpdateOption, "virt_text_max_lines", value)
    if not ok then
      vim.notify("Could not update Molten output lines: " .. tostring(err), vim.log.levels.ERROR)
      return
    end

    vim.notify("Molten maximum output lines: " .. value .. "; re-evaluate the cell to refresh its output")
  end)
end

local function reset_molten_output_lines(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local value = molten_default_output_lines()
  vim.b[buf].molten_virt_text_max_lines = nil
  if vim.api.nvim_get_current_buf() ~= buf or not vim.b[buf].molten_active then
    return
  end

  local ok, err = pcall(vim.fn.MoltenUpdateOption, "virt_text_max_lines", value)
  if not ok then
    vim.notify("Could not reset Molten output lines: " .. tostring(err), vim.log.levels.ERROR)
    return
  end

  vim.notify("Molten maximum output lines reset to " .. value .. "; re-evaluate the cell to refresh its output")
end

local function rerender_molten_images(buf, width, height)
  local ok, image = pcall(require, "image")
  if not ok then
    return false
  end

  local images = image.get_images({ buffer = buf, namespace = "molten" })
  table.sort(images, function(left, right)
    return (left.geometry.y or 0) < (right.geometry.y or 0)
  end)
  for _, current_image in ipairs(images) do
    current_image.global_state.options.max_width = width
    current_image.global_state.options.max_height = height
    current_image.geometry.width = width
    current_image.geometry.height = height
    current_image:clear()
    current_image:render()
  end

  return true
end

local function resize_molten_images(buf)
  local default_width = tonumber(vim.g.molten_image_max_width) or 100
  local default_height = tonumber(vim.g.molten_image_max_height) or 12
  local current_width = tonumber(vim.b[buf].molten_image_max_width) or default_width
  local current_height = tonumber(vim.b[buf].molten_image_max_height) or default_height

  vim.ui.input({
    prompt = "Molten image maximum width (columns): ",
    default = tostring(current_width),
  }, function(width_input)
    if width_input == nil then
      return
    end

    local width = tonumber(width_input)
    if not width or width < 1 or width % 1 ~= 0 then
      vim.notify("Molten image width must be a positive integer", vim.log.levels.ERROR)
      return
    end

    vim.ui.input({
      prompt = "Molten image maximum height (rows): ",
      default = tostring(current_height),
    }, function(height_input)
      if height_input == nil then
        return
      end

      local height = tonumber(height_input)
      if not height or height < 1 or height % 1 ~= 0 then
        vim.notify("Molten image height must be a positive integer", vim.log.levels.ERROR)
        return
      end

      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      vim.b[buf].molten_image_max_width = width
      vim.b[buf].molten_image_max_height = height

      if not rerender_molten_images(buf, width, height) then
        vim.notify("image.nvim is unavailable", vim.log.levels.ERROR)
        return
      end

      vim.notify(("Molten image size: %d columns × %d rows"):format(width, height))
    end)
  end)
end

local function reset_molten_image_size(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local width = tonumber(vim.g.molten_image_max_width) or 100
  local height = tonumber(vim.g.molten_image_max_height) or 12
  vim.b[buf].molten_image_max_width = nil
  vim.b[buf].molten_image_max_height = nil

  if not rerender_molten_images(buf, width, height) then
    vim.notify("image.nvim is unavailable", vim.log.levels.ERROR)
    return
  end

  vim.notify(("Molten image size reset to %d columns × %d rows"):format(width, height))
end

local function apply_molten_image_size(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.b[buf].molten_active then
    return
  end

  local ok, image = pcall(require, "image")
  if not ok then
    return
  end

  local width = tonumber(vim.b[buf].molten_image_max_width)
    or tonumber(vim.g.molten_image_max_width)
    or 100
  local height = tonumber(vim.b[buf].molten_image_max_height)
    or tonumber(vim.g.molten_image_max_height)
    or 12
  for _, current_image in ipairs(image.get_images({ buffer = buf, namespace = "molten" })) do
    current_image.global_state.options.max_width = width
    current_image.global_state.options.max_height = height
  end
end

local function add_molten_controls(buf)
  buffer_map(buf, "<leader>Rd", "<cmd>MoltenDeinit<cr>", "Deinitialize Molten")
  buffer_map(buf, "<leader>Ro", function()
    set_molten_output_lines(buf)
  end, "Set Molten output lines")
  buffer_map(buf, "<leader>RO", function()
    reset_molten_output_lines(buf)
  end, "Reset Molten output lines")
  buffer_map(buf, "<leader>Rz", function()
    resize_molten_images(buf)
  end, "Resize Molten images")
  buffer_map(buf, "<leader>RZ", function()
    reset_molten_image_size(buf)
  end, "Reset Molten image size")
  sync_backend_controls(buf)
end

-- All send commands converge here so Slime, Iron, and Molten receive the same
-- ranges even though their transport APIs differ.
local function get_lines(start_line, end_line)
  return vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
end

local function send_range(start_line, end_line, start_col, end_col)
  local backend = require_backend()
  if not backend or start_line > end_line then
    return
  end

  if backend == "slime" then
    vim.fn["slime#send_range"](start_line, end_line)
  elseif backend == "iron" then
    local filetype = iron_filetype(vim.api.nvim_get_current_buf())
    if filetype then
      require("iron.core").send(filetype, table.concat(get_lines(start_line, end_line), "\n") .. "\n")
    end
  else
    vim.fn.MoltenEvaluateRange(start_line, end_line, start_col or 1, end_col or -1)
  end
end

-- Source files use language-specific cell markers such as `# %%`; Quarto cell
-- boundaries are supplied by quarto-nvim through M.run_quarto_cell below.
local function current_cell_range()
  local delimiter = vim.b.slime_cell_delimiter
  if not delimiter then
    vim.notify("No cell delimiter configured for " .. vim.bo.filetype, vim.log.levels.WARN)
    return
  end

  local previous_cell = vim.fn.search(delimiter, "bcnW")
  local next_cell = vim.fn.search(delimiter, "nW")
  local start_line = previous_cell > 0 and previous_cell + 1 or 1
  local end_line = next_cell > 0 and next_cell - 1 or vim.api.nvim_buf_line_count(0)

  return start_line, end_line, next_cell
end

local function set_cell_delimiter(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local delimiter = cell_delimiters[vim.bo[buf].filetype]
  if delimiter then
    vim.b[buf].slime_cell_delimiter = delimiter
  end
end

function M.send_cell(move_to_next)
  local start_line, end_line, next_cell = current_cell_range()
  if not start_line then
    return
  end

  send_range(start_line, end_line)

  if move_to_next and next_cell > 0 then
    vim.api.nvim_win_set_cursor(0, { math.min(next_cell + 1, vim.api.nvim_buf_line_count(0)), 0 })
  end
end

function M.send_cells(direction)
  local start_line, end_line = current_cell_range()
  if not start_line then
    return
  end

  if direction == "above" then
    send_range(1, end_line)
  else
    send_range(start_line, vim.api.nvim_buf_line_count(0))
  end
end

function M.send_line()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  send_range(line, line)
end

function M.send_paragraph()
  local previous_blank = vim.fn.search([[^\s*$]], "bnW")
  local next_blank = vim.fn.search([[^\s*$]], "nW")
  local start_line = previous_blank > 0 and previous_blank + 1 or 1
  local end_line = next_blank > 0 and next_blank - 1 or vim.api.nvim_buf_line_count(0)
  send_range(start_line, end_line)
end

function M.send_all()
  send_range(1, vim.api.nvim_buf_line_count(0))
end

function M.send_visual()
  local backend = require_backend()
  if not backend then
    return
  end

  if backend == "slime" then
    vim.fn["slime#send_op"](vim.fn.visualmode(), 1)
    return
  elseif backend == "molten" then
    vim.cmd("MoltenEvaluateVisual")
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local filetype = iron_filetype(buf)
  if filetype then
    local iron = require("iron.core")
    iron.attach(filetype, buf)
    iron.visual_send()
  end
end

function M.send_motion()
  local backend = require_backend()
  if not backend then
    return
  end

  if backend == "slime" then
    local keys = vim.api.nvim_replace_termcodes("<Plug>SlimeMotionSend", true, false, true)
    vim.api.nvim_feedkeys(keys, "m", false)
  elseif backend == "iron" then
    local buf = vim.api.nvim_get_current_buf()
    local filetype = iron_filetype(buf)
    if filetype then
      local iron = require("iron.core")
      iron.attach(filetype, buf)
      iron.run_motion("send_motion")
    end
  else
    vim.cmd("MoltenEvaluateOperator")
  end
end

-- Contextual <leader>Rt action: configure Slime, open Iron, or initialize a
-- Molten kernel without exposing backend-specific commands to the caller.
function M.configure_backend()
  local backend = require_backend()
  if backend == "slime" then
    vim.cmd("SlimeConfig")
  elseif backend == "iron" then
    local filetype = iron_filetype(vim.api.nvim_get_current_buf())
    if filetype then
      require("iron.core").repl_for(filetype)
    end
  elseif backend == "molten" then
    vim.cmd("MoltenInit")
  end
end

-- Select a backend for the current buffer and immediately replace its
-- backend-specific controls and status-line value.
function M.select_backend()
  local buf = vim.api.nvim_get_current_buf()
  vim.ui.select(backends, {
    prompt = "REPL backend",
    format_item = function(backend)
      return backend .. (backend_available(backend) and "" or " (unavailable)")
    end,
  }, function(backend)
    if not backend then
      return
    end
    if not backend_available(backend) then
      vim.notify("REPL backend '" .. backend .. "' is unavailable", vim.log.levels.ERROR)
      return
    end

    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end

    vim.b[buf].repl_backend = backend
    sync_backend_controls(buf)
    vim.cmd.redrawstatus()
    vim.notify("REPL backend: " .. backend)
  end)
end

-- Adapter used by quarto-nvim's codeRunner so Quarto chunks share the backend
-- chosen for ordinary source files instead of maintaining a second runner.
function M.run_quarto_cell(cell, ignore_cols)
  local backend = require_backend()
  if backend then
    if backend == "iron" and cell.lang then
      vim.b.iron_repl_filetype = cell.lang
    end
    require("quarto.runner." .. backend).run(cell, ignore_cols)
  end
end

-- Attach the <leader>R group and cell delimiter to supported source/Quarto
-- buffers. Autocommands also reapply buffer-local Molten display settings.
function M.setup()
  vim.g.repl_backend = vim.g.repl_backend or "slime"

  vim.keymap.set("n", "<leader>Rc", function()
    M.send_cell(false)
  end, { desc = "Send current cell" })
  vim.keymap.set("n", "<leader>Rn", function()
    M.send_cell(true)
  end, { desc = "Send current cell and move next" })
  vim.keymap.set("n", "<leader>Ra", function()
    M.send_cells("above")
  end, { desc = "Send current cell and above" })
  vim.keymap.set("n", "<leader>Rb", function()
    M.send_cells("below")
  end, { desc = "Send current cell and below" })
  vim.keymap.set("n", "<leader>Rl", M.send_line, { desc = "Send current line" })
  vim.keymap.set("n", "<leader>Rp", M.send_paragraph, { desc = "Send paragraph" })
  vim.keymap.set("n", "<leader>Rm", M.send_motion, { desc = "Send motion" })
  vim.keymap.set("x", "<leader>Rs", M.send_visual, { desc = "Send selection" })
  vim.keymap.set("n", "<leader>RA", M.send_all, { desc = "Send entire buffer" })
  vim.keymap.set("n", "<leader>Re", M.select_backend, { desc = "Select REPL backend" })
  vim.keymap.set("n", "<leader>Rt", M.configure_backend, { desc = "Initialize/configure backend" })

  local has_which_key, which_key = pcall(require, "which-key")
  if has_which_key then
    which_key.add({
      { "<leader>R", group = "repl", icon = { icon = " ", color = "green" } },
    })
  end

  local group = vim.api.nvim_create_augroup("repl_config", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = vim.tbl_keys(cell_delimiters),
    callback = function(event)
      set_cell_delimiter(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MoltenInitPost",
    callback = function(event)
      local buf = event.buf == 0 and vim.api.nvim_get_current_buf() or event.buf
      vim.b[buf].molten_active = true
      add_molten_controls(buf)
      apply_molten_output_lines(buf)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MoltenDeinitPost",
    callback = function(event)
      local buf = event.buf == 0 and vim.api.nvim_get_current_buf() or event.buf
      vim.b[buf].molten_active = nil
      pcall(vim.keymap.del, "n", "<leader>Rd", { buffer = buf })
      pcall(vim.keymap.del, "n", "<leader>Ro", { buffer = buf })
      pcall(vim.keymap.del, "n", "<leader>RO", { buffer = buf })
      pcall(vim.keymap.del, "n", "<leader>Rz", { buffer = buf })
      pcall(vim.keymap.del, "n", "<leader>RZ", { buffer = buf })
      sync_backend_controls(buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(event)
      sync_backend_controls(event.buf)
      apply_molten_output_lines(event.buf)
      apply_molten_image_size(event.buf)
    end,
  })

  local current_buf = vim.api.nvim_get_current_buf()
  set_cell_delimiter(current_buf)
  sync_backend_controls(current_buf)
end

return M
