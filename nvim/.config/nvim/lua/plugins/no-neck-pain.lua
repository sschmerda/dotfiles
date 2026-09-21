return {
  {
    "shortcuts/no-neck-pain.nvim",
    lazy = false,
    opts = {
      width = 120,
      autocmds = {
        -- v3 enable() is synchronous; defer startup until the window layout settles.
        enableOnVimEnter = "safe",
        enableOnTabEnter = true,
      },
    },
    config = function(_, opts)
      local nnp = require("no-neck-pain")
      local suspended = {}
      local initialized = {}
      local restore_focus
      opts.callbacks = {
        postDisable = function()
          -- Disabling normally focuses the original window; keep the user's new split focused.
          if restore_focus and vim.api.nvim_win_is_valid(restore_focus) then
            vim.api.nvim_set_current_win(restore_focus)
          end
          restore_focus = nil
        end,
      }
      nnp.setup(opts)

      local generation = 0
      vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "WinClosed", "TabEnter" }, {
        group = vim.api.nvim_create_augroup("NoNeckPainSingleWindow", { clear = true }),
        callback = function()
          generation = generation + 1
          local current = generation
          -- Wait for split creation/closure and the plugin's own layout handlers to finish.
          vim.defer_fn(function()
            if current ~= generation or vim.v.exiting ~= vim.NIL or vim.g.SessionLoad then
              return
            end
            local tab = vim.api.nvim_get_current_tabpage()
            local windows = {}
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
              local buf = vim.api.nvim_win_get_buf(win)
              if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].filetype ~= "no-neck-pain" then
                windows[#windows + 1] = win
              end
            end
            local active = nnp.state and nnp.state.tabs and nnp.state.tabs[tab] ~= nil
            if active then
              initialized[tab] = true
            end
            if #windows > 1 and active then
              suspended[tab] = true
              restore_focus = vim.api.nvim_get_current_win()
              nnp.disable()
            elseif #windows == 1 and (suspended[tab] or not initialized[tab]) then
              -- Also initialize new tabs while the plugin is globally suspended.
              -- Once initialized, only undo our own suspension, preserving manual toggles.
              if vim.api.nvim_get_current_win() == windows[1] and vim.bo.buftype == "" and vim.bo.filetype ~= "" then
                nnp.enable()
                initialized[tab] = true
                suspended[tab] = nil
              end
            end
          end, 30)
        end,
      })
    end,
  },
}
