return
{
  "NeogitOrg/neogit",
  keys = {
        -- Overwrite gg to open Neogit instead of LazyGit
        vim.api.nvim_set_keymap('n', '<leader>gg', ':Neogit cwd=' .. LazyVim.root.get() .. '<CR>', { noremap = true, silent = true }),
        vim.api.nvim_set_keymap('n', '<leader>gG', ':Neogit<CR>', { noremap = true, silent = true })
        },
  dependencies = {
    "nvim-lua/plenary.nvim",         -- required
    "sindrets/diffview.nvim",        -- optional - Diff integration

    -- Only one of these is needed.
    "nvim-telescope/telescope.nvim", -- optional
    "ibhagwan/fzf-lua",              -- optional
    "echasnovski/mini.pick",         -- optional
  },
  config = true
}
