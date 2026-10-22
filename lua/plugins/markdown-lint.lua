return {
  "mfussenegger/nvim-lint",
  opts = {
    linters = {
      ["markdownlint-cli2"] = {
        condition = function(ctx)
          return not ctx.filename:match("^%a[%w+.-]*://")
        end,
      },
    },
  },
}
