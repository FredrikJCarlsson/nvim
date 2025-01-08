return {
    {
      "nvim-neorg/neorg",
      lazy = false,
      version = "*",
      config = function()
        require("neorg").setup {
          load = {
            ["core.defaults"] = {},
            ["core.concealer"] = {},
            ["core.export"] = {},
            ["core.export.markdown"] = {},
            ["core.highlights"] = {},
            ["core.integrations.treesitter"] = {},
            ["core.summary"] = {},
            ["core.dirman"] = {
              config = {
                workspaces = {
                    notes = "~/OneDrive - Unipower AB/Dokument/neorg/notes",   -- Notes workspace
                },
                default_workspace = "notes",
              },
            },
            ["core.keybinds"] = {
                config = {
                    default_keybinds = true,
                },
            }
          },
        }
        vim.wo.foldlevel = 99
        vim.wo.conceallevel = 0
      end,
    },
}
