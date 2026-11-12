return {
  {
    "pwntester/octo.nvim",
    opts = {
      -- LazyVim enables this by default; project timeline queries require read:project.
      -- Keep PRs and reviews usable with the existing GitHub CLI token scopes.
      default_to_projects_v2 = false,
    },
  },
}
