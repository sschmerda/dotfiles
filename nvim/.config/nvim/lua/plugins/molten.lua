-- Molten is the Jupyter-kernel backend. It keeps textual results as virtual
-- text and plots as image.nvim virtual images below executed code cells.
-- config.repl owns initialization, execution, output limits, and image sizing.
local in_devcontainer = vim.fn.filereadable("/.dockerenv") == 1
local outer_tmux_state_path = vim.env.DEVCONTAINER_OUTER_TMUX_STATE
local outer_tmux_bridge = nil

if
  in_devcontainer
  and vim.env.DEVCONTAINER_OUTER_TMUX == "1"
  and type(outer_tmux_state_path) == "string"
  and outer_tmux_state_path ~= ""
then
  outer_tmux_bridge = {
    path = outer_tmux_state_path,
    state = nil,
    applying = false,
    apply_pending = false,
    refresh_pending = false,
    watcher = nil,
    refresh_timer = nil,
  }
end

local function is_nonnegative_integer(value)
  return type(value) == "number" and value >= 0 and value == math.floor(value)
end

local function read_outer_tmux_state(bridge)
  local ok, lines = pcall(vim.fn.readfile, bridge.path, "", 1)
  if not ok or #lines ~= 1 then
    return nil, "state file is unavailable"
  end

  local decoded_ok, decoded = pcall(vim.json.decode, lines[1])
  if not decoded_ok or type(decoded) ~= "table" then
    return nil, "state file does not contain valid JSON"
  end

  if
    decoded.version ~= 1
    or not is_nonnegative_integer(decoded.screen_left)
    or not is_nonnegative_integer(decoded.screen_top)
    or not is_nonnegative_integer(decoded.pane_width)
    or decoded.pane_width == 0
    or not is_nonnegative_integer(decoded.pane_height)
    or decoded.pane_height == 0
    or not is_nonnegative_integer(decoded.image_zindex)
    or decoded.image_zindex == 0
    or decoded.image_zindex > 2147483647
    or type(decoded.visible) ~= "boolean"
  then
    return nil, "state file contains invalid pane geometry"
  end

  return {
    pane_id = decoded.pane_id,
    session_id = decoded.session_id,
    window_id = decoded.window_id,
    left = decoded.screen_left,
    top = decoded.screen_top,
    width = decoded.pane_width,
    height = decoded.pane_height,
    image_zindex = decoded.image_zindex,
    visible = decoded.visible,
  }
end

local function same_outer_tmux_state(left, right)
  return left
    and right
    and left.pane_id == right.pane_id
    and left.session_id == right.session_id
    and left.window_id == right.window_id
    and left.left == right.left
    and left.top == right.top
    and left.width == right.width
    and left.height == right.height
    and left.image_zindex == right.image_zindex
    and left.visible == right.visible
end

local function refresh_outer_tmux_state(bridge)
  local next_state, err = read_outer_tmux_state(bridge)
  if not next_state then
    return nil, false, err
  end

  local changed = not same_outer_tmux_state(bridge.state, next_state)
  bridge.state = next_state
  return next_state, changed, nil
end

local function apply_outer_tmux_state(bridge)
  if bridge.applying or not bridge.state then
    return
  end

  local ok, image = pcall(require, "image")
  if not ok then
    return
  end

  bridge.applying = true
  local applied, apply_err = xpcall(function()
    local images = image.get_images()
    for _, current_image in ipairs(images) do
      if current_image.is_rendered then
        current_image:clear(true)
      end
    end
    if bridge.state.visible then
      for _, current_image in ipairs(images) do
        current_image:render()
      end
    end
  end, debug.traceback)
  bridge.applying = false
  if not applied then
    vim.notify("Host tmux image bridge redraw failed: " .. apply_err, vim.log.levels.ERROR)
  end
end

local function schedule_outer_tmux_apply(bridge)
  if bridge.apply_pending then
    return
  end

  bridge.apply_pending = true
  vim.schedule(function()
    bridge.apply_pending = false
    apply_outer_tmux_state(bridge)
  end)
end

local function schedule_outer_tmux_refresh(bridge)
  if bridge.refresh_pending then
    return
  end

  bridge.refresh_pending = true
  vim.defer_fn(function()
    bridge.refresh_pending = false
    local _, changed, err = refresh_outer_tmux_state(bridge)
    if err then
      vim.notify_once("Host tmux image bridge: " .. err, vim.log.levels.WARN)
      return
    end
    if changed then
      schedule_outer_tmux_apply(bridge)
    end
  end, 20)
end

local function setup_outer_tmux_watcher(bridge)
  local uv = vim.uv or vim.loop
  local directory = vim.fs.dirname(bridge.path)
  local watcher = uv.new_fs_event()

  if watcher then
    local ok, started = pcall(watcher.start, watcher, directory, {}, function(err, _)
      if err then
        vim.schedule(function()
          vim.notify_once("Host tmux image bridge watcher: " .. err, vim.log.levels.WARN)
        end)
        return
      end
      vim.schedule(function()
        schedule_outer_tmux_refresh(bridge)
      end)
    end)
    if ok and started then
      bridge.watcher = watcher
    else
      watcher:close()
    end
  end

  -- Docker Desktop may not forward host-side file events or inode changes
  -- through a bind mount. Read the single small state line at a low fixed rate
  -- as a deterministic fallback; rendering itself always uses cached Lua data.
  local refresh_timer = uv.new_timer()
  if refresh_timer then
    local ok, started = pcall(refresh_timer.start, refresh_timer, 250, 250, function()
      vim.schedule(function()
        schedule_outer_tmux_refresh(bridge)
      end)
    end)
    if ok and started then
      bridge.refresh_timer = refresh_timer
    else
      refresh_timer:close()
    end
  end

  local group = vim.api.nvim_create_augroup("molten_outer_tmux_bridge", { clear = true })
  vim.api.nvim_create_autocmd({ "FocusGained", "FocusLost", "VimResized" }, {
    group = group,
    callback = function()
      schedule_outer_tmux_refresh(bridge)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if bridge.watcher and not bridge.watcher:is_closing() then
        bridge.watcher:stop()
        bridge.watcher:close()
      end
      bridge.watcher = nil
      if bridge.refresh_timer and not bridge.refresh_timer:is_closing() then
        bridge.refresh_timer:stop()
        bridge.refresh_timer:close()
      end
      bridge.refresh_timer = nil
    end,
  })
end

local function setup_image_nvim(_, opts)
  if in_devcontainer then
    -- Match image.nvim's own module names exactly. Lua caches slash- and
    -- dot-separated require names independently even when they resolve to the
    -- same file, so using dot names would patch an unused module instance.
    local term = require("image/utils/term")

    if not term.molten_devcontainer_tty_applied then
      local get_tty = term.get_tty
      term.get_tty = function()
        local uv = vim.uv or vim.loop
        local resolved = uv and uv.fs_readlink and uv.fs_readlink("/proc/self/fd/1") or nil
        if type(resolved) == "string" and resolved:match("^/dev/") then
          return resolved
        end

        local tty = get_tty()
        if type(tty) == "string" and tty:match("^/dev/") then
          return tty
        end

        return nil
      end
      term.molten_devcontainer_tty_applied = true
    end

    -- Host Ghostty cannot open image paths inside the container. image.nvim
    -- selects direct Kitty transmission for SSH sessions, so use that path for
    -- this Neovim process and load the backend only after fixing TTY discovery.
    if not vim.env.SSH_CLIENT and not vim.env.SSH_TTY then
      vim.env.SSH_CLIENT = "devcontainer"
    end

    local utils = require("image/utils")
    if outer_tmux_bridge then
      if vim.env.TMUX then
        error("Host tmux image bridge does not support an additional tmux inside the container")
      end

      local state, _, err = refresh_outer_tmux_state(outer_tmux_bridge)
      if not state then
        error("Host tmux image bridge: " .. err)
      end

      -- Model the invisible host tmux transport without exposing its socket.
      -- image.nvim can then reuse its native DCS wrapper while every tmux query
      -- is answered by the live, read-only bridge state.
      utils.tmux.is_tmux = true
      utils.tmux.has_passthrough = true
      utils.tmux.get_pane_position = function()
        local current = outer_tmux_bridge.state
        return { left = current.left, top = current.top }
      end
      utils.tmux.get_pane_left = function()
        return outer_tmux_bridge.state.left
      end
      utils.tmux.get_pane_top = function()
        return outer_tmux_bridge.state.top
      end
      utils.tmux.get_pane_id = function()
        return outer_tmux_bridge.state.pane_id
      end
      utils.tmux.get_window_id = function()
        return outer_tmux_bridge.state.window_id
      end
      utils.tmux.get_current_session = function()
        return outer_tmux_bridge.state.session_id
      end
      utils.tmux.get_pane_tty = term.get_tty
      utils.tmux.get_cursor_x = function() end
      utils.tmux.get_cursor_y = function() end
      opts.tmux_show_only_in_active_window = false
    end

    local backend = require("image/backends/kitty")
    local helpers = require("image/backends/kitty/helpers")
    if not backend.molten_devcontainer_placement_applied then
      local codes = require("image/backends/kitty/codes")
      local active_width, active_height
      local backend_render = backend.render

      backend.render = function(image, x, y, width, height)
        if outer_tmux_bridge then
          local state = outer_tmux_bridge.state
          if not state or not state.visible then
            return false
          end
        end

        active_width, active_height = width, height
        local ok, result = xpcall(function()
          return backend_render(image, x, y, width, height)
        end, debug.traceback)
        active_width, active_height = nil, nil
        if not ok then
          error(result)
        end
        return result
      end

      local function graphics_control_sequence(config)
        local control = {}
        for name, value in pairs(config) do
          local key = codes.control.keys[name]
          if key and value ~= nil then
            if type(value) == "number" then
              value = string.format("%d", value)
            end
            control[#control + 1] = key .. "=" .. tostring(value)
          end
        end
        return "\x1b_G" .. table.concat(control, ",") .. "\x1b\\"
      end

      helpers.write_graphics_at = function(config, x, y)
        config = vim.deepcopy(config)
        config.display_zindex = outer_tmux_bridge and outer_tmux_bridge.state.image_zindex or 0

        -- Kitty's w/h fields crop the source image while c/r size the
        -- destination. Use the cropped pixel rectangle for c/r; retaining the
        -- full dimensions here stretches the last visible rows while scrolling.
        local term_size = term.get_size()
        local cell_width = term_size and tonumber(term_size.cell_width) or nil
        local cell_height = term_size and tonumber(term_size.cell_height) or nil
        local display_width = tonumber(config.display_width)
        local display_height = tonumber(config.display_height)
        if cell_width and cell_width > 0 and display_width then
          config.display_columns = math.max(1, math.ceil(display_width / cell_width))
        else
          config.display_columns = active_width or config.display_columns
        end
        if cell_height and cell_height > 0 and display_height then
          config.display_rows = math.max(1, math.ceil(display_height / cell_height))
        else
          config.display_rows = active_height or config.display_rows
        end

        if utils.tmux.is_tmux then
          local pane = utils.tmux.get_pane_position()
          x = x + pane.left
          y = y + pane.top
        end

        local tty = term.get_tty()
        if not tty then
          error("image.nvim: could not resolve the devcontainer terminal")
        end

        local sequence = "\x1b[?2026h\x1b[s\x1b["
          .. y
          .. ";"
          .. x
          .. "H"
          .. graphics_control_sequence(config)
          .. "\x1b[u\x1b[?2026l"
        helpers.write(sequence, tty, true)
      end

      backend.molten_devcontainer_placement_applied = true
    end
  end

  require("image").setup(opts)
  if outer_tmux_bridge then
    setup_outer_tmux_watcher(outer_tmux_bridge)
  end
end

return {
  {
    "benlubas/molten-nvim",
    version = "^1.0.0",
    build = ":UpdateRemotePlugins",
    dependencies = {
      {
        "3rd/image.nvim",
        -- magick_cli uses the system ImageMagick binary; do not build the
        -- optional Lua rock or provision hererocks in minimal containers.
        build = false,
        opts = {
          backend = "kitty",
          kitty_method = "normal",
          processor = "magick_cli",
          max_width = 100,
          max_height = 12,
          max_width_window_percentage = math.huge,
          max_height_window_percentage = math.huge,
          tmux_show_only_in_active_window = true,
          editor_only_render_when_focused = false,
          window_overlap_clear_enabled = not in_devcontainer,
          integrations = {
            markdown = { enabled = false },
          },
        },
        config = setup_image_nvim,
      },
    },
    lazy = false,
    init = function()
      -- Discover kernels installed inside the currently active conda/micromamba
      -- environment without requiring a global kernelspec registration.
      if vim.env.CONDA_PREFIX then
        local conda_jupyter = vim.env.CONDA_PREFIX .. "/share/jupyter"
        vim.env.JUPYTER_PATH = conda_jupyter
          .. (vim.env.JUPYTER_PATH and ":" .. vim.env.JUPYTER_PATH or "")
      end

      -- This provider runs Molten's Neovim remote plugin; it is deliberately
      -- separate from the project environment that runs the selected kernel.
      local python = vim.fn.stdpath("data") .. "/molten-venv/bin/python"
      if vim.fn.executable(python) == 1 then
        vim.g.python3_host_prog = python
      end

      vim.g.molten_auto_open_output = false
      vim.g.molten_auto_image_popup = false
      vim.g.molten_image_provider = "image.nvim"
      vim.g.molten_image_location = "virt"
      vim.g.molten_image_max_width = 100
      vim.g.molten_image_max_height = 12
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_text_max_lines = 40
      vim.g.molten_virt_lines_off_by_1 = false

      -- The host-specific placement adjustments below conflict with Ghostty's
      -- Docker PTY path. Keep Molten's default virtual-line placement there.
      if in_devcontainer then
        return
      end

      local function set_virt_lines_offset(enabled)
        local ok, status = pcall(require, "molten.status")
        if ok and status.initialized() == "Molten" then
          vim.fn.MoltenUpdateOption("virt_lines_off_by_1", enabled)
        else
          vim.g.molten_virt_lines_off_by_1 = enabled
        end
      end

      local group = vim.api.nvim_create_augroup("molten_output_placement", { clear = true })
      vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        pattern = { "*.qmd", "*.md", "*.ipynb" },
        callback = function(event)
          if not event.file:match("%.otter%.") then
            set_virt_lines_offset(true)
          end
        end,
      })
      vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        pattern = "*.py",
        callback = function(event)
          if not event.file:match("%.otter%.") then
            set_virt_lines_offset(false)
          end
        end,
      })
    end,
    config = function()
      if in_devcontainer then
        -- Preserve the namespace used by the buffer-local image resize controls
        -- without applying the host-specific render offsets below.
        local bridge = require("load_image_nvim").image_api
        if not bridge.molten_devcontainer_namespace_applied then
          local from_file = bridge.from_file
          bridge.from_file = function(path, opts)
            opts = opts or {}
            opts.namespace = opts.namespace or "molten"
            return from_file(path, opts)
          end
          bridge.molten_devcontainer_namespace_applied = true
        end
        return
      end

      -- Normal Kitty placement scrolls smoothly in Ghostty/tmux. Partial top
      -- cropping is unreliable in that stack, so Molten images are hidden when
      -- their anchor reaches the viewport top; bottom cropping remains native.
      -- Kitty graphics passed through tmux use terminal coordinates. tmux's
      -- pane_top excludes a status bar at the top, so add those rows at the
      -- final placement boundary while preserving Kitty's native cropping.
      if vim.env.TMUX then
        local helpers = require("image.backends.kitty.helpers")
        if not helpers.molten_top_status_offset_applied then
          local status = vim.fn.system({ "tmux", "display-message", "-p", "#{status-position} #{status}" })
          local shell_error = vim.v.shell_error
          local position, value = vim.trim(status):match("^(%S+)%s+(%S+)$")
          local status_lines = tonumber(value) or (value == "on" and 1 or 0)
          if shell_error == 0 and position == "top" and status_lines > 0 then
            local write_graphics_at = helpers.write_graphics_at
            helpers.write_graphics_at = function(graphics, x, y)
              return write_graphics_at(graphics, x, y + status_lines)
            end
          end
          helpers.molten_top_status_offset_applied = true
        end
      end

      -- Leave room for the fenced block boundary and Molten's output header.
      -- Offset only images created through Molten's image.nvim bridge.
      local bridge = require("load_image_nvim").image_api
      if not bridge.molten_render_offset_applied then
        local image_buffers = {}
        local from_file = bridge.from_file
        bridge.from_file = function(path, opts)
          opts = opts or {}
          opts.render_offset_top = opts.render_offset_top or 3
          opts.namespace = opts.namespace or "molten"
          local identifier = from_file(path, opts)
          if type(opts.buffer) == "number" then
            image_buffers[identifier] = opts.buffer
          end
          return identifier
        end

        local render = bridge.render
        bridge.render = function(identifier, geometry)
          local buf = image_buffers[identifier]
          if buf and vim.api.nvim_buf_is_valid(buf) then
            local width = tonumber(vim.b[buf].molten_image_max_width)
              or tonumber(vim.g.molten_image_max_width)
              or 100
            local height = tonumber(vim.b[buf].molten_image_max_height)
              or tonumber(vim.g.molten_image_max_height)
              or 12
            geometry = geometry or {}
            geometry.width = width
            geometry.height = height
          end

          local result = render(identifier, geometry)

          -- load_image_nvim registers a new image only during its first render,
          -- so install per-image behavior after delegating to it.
          if buf and vim.api.nvim_buf_is_valid(buf) then
            local ok, image = pcall(require, "image")
            if ok then
              for _, current_image in ipairs(image.get_images({ buffer = buf, namespace = "molten" })) do
                if not current_image.molten_hide_at_top_applied then
                  local image_render = current_image.render
                  current_image.render = function(self, next_geometry)
                    local image_row = (next_geometry and next_geometry.y) or self.geometry.y
                    local win_info = self.window and vim.fn.getwininfo(self.window)[1] or nil
                    if win_info and image_row + 1 <= win_info.topline then
                      -- Clear only the Kitty placement. Keep the image object,
                      -- extmark, and virtual padding so scrolling down restores it.
                      if self.is_rendered then
                        self.global_state.backend.clear(self.id, true)
                      end
                      return false
                    end
                    return image_render(self, next_geometry)
                  end
                  current_image.molten_hide_at_top_applied = true
                end
                current_image.global_state.options.max_width = geometry.width
                current_image.global_state.options.max_height = geometry.height
              end
            end
          end

          return result
        end
        bridge.molten_render_offset_applied = true
      end
    end,
  },
}
