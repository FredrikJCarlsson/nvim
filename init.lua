-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
vim.g.autoformat = false


-- require('snacks').setup {
--   pickers = {
--     rga_snacks = {
--       cmd = "rga",
--       args = { '--json' },
--       format = function(entry)
--         return entry.text -- Customize how results are displayed
--       end,
--     },
--   }
-- }

