return {
  "stevearc/conform.nvim",
  opts = {
    formatters = {
      csharpier = {
        command = "csharpier",
        args = { "format", "$FILENAME" },
        stdin = false,
      },
    },
    formatters_by_ft = {
      cs = { "csharpier" },
      cpp = { "clang_format" },
      c = { "clang_format" },
    },

  },
}
