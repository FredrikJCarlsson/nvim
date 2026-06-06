return {
    "mfussenegger/nvim-dap",
    opts = function()
        local dap = require("dap")

        if vim.fn.has("mac") == 1 then
            dap.defaults.fallback.external_terminal = {
                command = "/Applications/Ghostty.app/Contents/MacOS/ghostty",
                args = { "-e" },
            }
            dap.defaults.fallback.force_external_terminal = true
        end

        dap.adapters.codelldb = {
            type = "server",
            port = "${port}",
            executable = {
                command = vim.fn.exepath("codelldb"),
                args = { "--port", "${port}" },
            },
        }
    end,
}
