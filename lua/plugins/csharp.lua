-- C# tweaks: roslyn.nvim (see roslynLSP.lua) is the C# server, so disable the
-- OmniSharp server that the LazyVim lang.dotnet extra enables, and skip
-- illuminate's per-cursor-move documentHighlight requests in large C# solutions.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        omnisharp = { enabled = false },
      },
    },
  },
  {
    "RRethy/vim-illuminate",
    opts = function(_, opts)
      opts.filetypes_denylist = opts.filetypes_denylist or {}
      table.insert(opts.filetypes_denylist, "cs")
    end,
  },
}
