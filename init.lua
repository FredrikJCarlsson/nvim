-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
local omnisharpExtend = require('omnisharp_extended')

vim.g.autoformat = false

-- Org mode
-- Load custom treesitter grammar for org filetype
require('orgmode').setup_ts_grammar()

-- Treesitter configuration
require('nvim-treesitter.configs').setup {
  highlight = {
    enable = true,
  },
  ensure_installed = {'org'}, -- Or run :TSUpdate org
}

require('orgmode').setup({
  org_agenda_files = {'C:/Users/fredrik.j.carlsson/OneDrive - Unipower AB/OrgMode/*', '~/my-orgs/**/*'},
  org_default_notes_file = 'C:/Users/fredrik.j.carlsson/OneDrive - Unipower AB/OrgMode/refile.org',
})
