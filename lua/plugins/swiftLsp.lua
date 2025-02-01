return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      sourcekit = { -- Enable SourceKit-LSP
        cmd = { "sourcekit-lsp" }, -- Ensure `sourcekit-lsp` is in your PATH
        filetypes = { "swift", "objective-c", "objective-cpp" },
        root_dir = require("lspconfig.util").root_pattern("Package.swift", ".git"),
      },
    },
  },
}
