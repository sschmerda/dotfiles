-- Make Blink/friendly-snippets language-aware inside Quarto. The outer prose
-- uses Markdown snippets, while fenced chunks use their embedded language;
-- <leader>Ms additionally restricts normal Python files to Jupytext helpers.
local function quarto_snippet_filetype(context)
  if vim.bo[context.bufnr].filetype ~= "quarto" then
    return vim.bo[context.bufnr].filetype
  end

  local ok, parser = pcall(vim.treesitter.get_parser, context.bufnr)
  if not ok then
    return "quarto"
  end

  local row = math.max(context.cursor[1] - 1, 0)
  local col = math.max(context.cursor[2], 0)
  local tree_ok, tree = pcall(parser.language_for_range, parser, { row, col, row, col })
  if not tree_ok then
    return "quarto"
  end

  local language = tree and tree:lang() or "quarto"
  if language == "markdown" or language == "markdown_inline" then
    return "quarto"
  end

  return language == "latex" and "tex" or language
end

return {
  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      sources = {
        providers = {
          snippets = {
            opts = {
              extended_filetypes = {
                quarto = { "markdown" },
              },
              get_filetype = quarto_snippet_filetype,
            },
            transform_items = function(context, items)
              if vim.bo[context.bufnr].filetype ~= "python" or not vim.b[context.bufnr].jupytext_snippets_only then
                return items
              end

              return vim.tbl_filter(function(item)
                return item.label == "#cell" or item.label == "#mark"
              end, items)
            end,
          },
        },
      },
    },
  },
}
