-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

require("dap").set_log_level("DEBUG")
vim.g.autoformat = false
