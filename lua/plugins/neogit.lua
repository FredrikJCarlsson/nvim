return
{
  "NeogitOrg/neogit",
  dependencies = {
    "nvim-lua/plenary.nvim",         -- required
    -- "sindrets/diffview.nvim",        -- optional - Diff integration
  },
  lazy = false,
  keys = {
            {
                "<leader>gg",
                function()
                    require("neogit").open({cwd = LazyVim.root.get()})
                end,
                desc = "Open Neogit in project root"
            },
            {
                "<leader>gG",
                function()
                    require("neogit").open()
                end,
                desc = "Open Neogit"
            }
        },
  config = true
}
