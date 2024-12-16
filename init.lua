-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
local omnisharpExtend = require('omnisharp_extended')

require('dap').set_log_level('DEBUG')
vim.g.autoformat = false

