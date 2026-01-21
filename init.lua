-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
vim.g.autoformat = false
vim.o.clipboard = "unnamedplus"

local function paste()
  return {
    vim.fn.split(vim.fn.getreg(""), "\n"),
    vim.fn.getregtype(""),
  }
end

vim.g.clipboard = {
  name = "OSC 52",
  copy = {
    ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
    ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
  },
  paste = {
    ["+"] = paste,
    ["*"] = paste,
  },
}

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

