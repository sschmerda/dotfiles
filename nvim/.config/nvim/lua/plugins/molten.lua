-- Molten is the Jupyter-kernel backend. It keeps textual results as virtual
-- text and plots as image.nvim virtual images below executed code cells.
-- config.repl owns initialization, execution, output limits, and image sizing.
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
          window_overlap_clear_enabled = true,
          integrations = {
            markdown = { enabled = false },
          },
        },
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
