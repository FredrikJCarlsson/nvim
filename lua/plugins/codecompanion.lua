if true then return {} end
return {
    "olimorris/codecompanion.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-treesitter/nvim-treesitter",
    },
    opts = {

        prompt_library = {
            markdown = {
                dirs = {
                    "~/.config/opencode/skills/docker-devcontainer-workflows/",
                    "~/.config/opencode/skills/petalinux-2024-2/",
                },
            },
        },
        interactions = {
            chat = {
                -- You can specify an adapter by name and model (both ACP and HTTP)
                adapter = {
                    name = "copilot",
                    model = "gpt-5.2",
                },
            },
            -- Or, just specify the adapter by name
            inline = {
                adapter = "copilot",
                model = "gpt-5.2",
            },
            cmd = {
                adapter = "copilot",
                model = "gpt-5.2",
            },
            background = {
                adapter = {
                    name = "copilot",
                    model = "gpt-5.2",
                },
            },
        },
        -- NOTE: The log_level is in `opts.opts`
        opts = {
            log_level = "DEBUG", -- or "TRACE"
        },
    },
}
