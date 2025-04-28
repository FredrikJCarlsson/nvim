return {
  "stevearc/overseer.nvim",
  opts = {}, -- Load with default settings
  config = function()
    require("overseer").setup({
      templates = { "builtin", "user.zig_build" },
    })
  end,
}
