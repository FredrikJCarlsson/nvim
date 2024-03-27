return{
  'nvim-orgmode/orgmode',
  dependencies = {
    { 'nvim-treesitter/nvim-treesitter', lazy = true },
    { 'dhruvasagar/vim-table-mode', lazy = true },
    { 'akinsho/org-bullets.nvim', lazy = true },
    { 'lukas-reineke/headlines.nvim', lazy = true },
  },
  event = 'VeryLazy',
  config = function()
    -- Load treesitter grammar for org
    require('orgmode').setup_ts_grammar()

    -- Setup treesitter
    require('nvim-treesitter.configs').setup({
      highlight = {
        enable = true,
      },
      ensure_installed = { 'org' },
    })

    -- Setup orgmode
    require('orgmode').setup({
      org_agenda_files = {'C:/Users/fredrik.j.carlsson/OneDrive - Unipower AB/OrgMode/*'},
      org_default_notes_file = 'C:/Users/fredrik.j.carlsson/OneDrive - Unipower AB/OrgMode/refile.org',
    })


    -- Load custom treesitter grammar for org filetype
    require('orgmode').setup_ts_grammar()

    -- Treesitter configuration
    require('nvim-treesitter.configs').setup {
      highlight = {
        enable = true,
      },
      ensure_installed = {'org'}, -- Or run :TSUpdate org
    }
  end, 
}
