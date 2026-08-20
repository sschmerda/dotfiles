return {
  {
    "sindrets/diffview.nvim",
    cmd = {
      "DiffviewOpen",
      "DiffviewClose",
      "DiffviewFileHistory",
      "DiffviewToggleFiles",
      "DiffviewFocusFiles",
      "DiffviewRefresh",
    },
    keys = {
      -- Local working tree diffs
      {
        "<leader>gvu",
        "<cmd>DiffviewOpen<cr>",
        desc = "Unstaged changes",
      },
      {
        "<leader>gvs",
        "<cmd>DiffviewOpen --cached<cr>",
        desc = "Staged changes",
      },
      {
        "<leader>gva",
        "<cmd>DiffviewOpen HEAD<cr>",
        desc = "All local changes",
      },

      -- Branch review diffs
      {
        "<leader>gvo",
        "<cmd>DiffviewOpen origin/main...HEAD --imply-local<cr>",
        desc = "Open vs origin/main",
      },
      {
        "<leader>gvO",
        "<cmd>DiffviewOpen main...HEAD --imply-local<cr>",
        desc = "Open vs local main",
      },
      {
        "<leader>gvm",
        "<cmd>DiffviewOpen origin/master...HEAD --imply-local<cr>",
        desc = "Open vs origin/master",
      },
      {
        "<leader>gvM",
        "<cmd>DiffviewOpen master...HEAD --imply-local<cr>",
        desc = "Open vs local master",
      },

      -- Diffview controls
      {
        "<leader>gvc",
        "<cmd>DiffviewClose<cr>",
        desc = "Close",
      },
      {
        "<leader>gvf",
        "<cmd>DiffviewToggleFiles<cr>",
        desc = "Toggle files",
      },
      {
        "<leader>gvr",
        "<cmd>DiffviewRefresh<cr>",
        desc = "Refresh",
      },
      {
        "<leader>gvh",
        "<cmd>DiffviewFileHistory %<cr>",
        desc = "Current file history",
      },
      {
        "<leader>gvH",
        "<cmd>DiffviewFileHistory<cr>",
        desc = "Repo history",
      },
    },
    opts = {
      view = {
        default = {
          layout = "diff2_horizontal",
        },
        file_history = {
          layout = "diff2_horizontal",
        },
      },
    },
  },

  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      table.insert(opts.spec, {
        mode = { "n" },
        { "<leader>gv", group = "diffview" },
      })
    end,
  },
}
