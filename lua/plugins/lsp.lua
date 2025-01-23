return {
    "neovim/nvim-lspconfig",
    opts = {
        servers = {
            sourcekit = {
            cmd = { "xcrun", "sourcekit-lsp" },
            filetypes = { "swift", "objective-c", "objective-cpp" },
            },
        },
        format = {
            formatting_options = nil,
            timeout_ms = 2000,
            },
            on_attach = function(client, bufnr)
            if client.name == "sourcekit" then
                vim.api.nvim_create_autocmd("BufWritePre", {
                buffer = bufnr,
                callback = function()
                    vim.fn.jobstart("swift-format -i " .. vim.fn.expand("%"))
                end,
                })
            end
        end,
  },
}
