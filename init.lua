-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
vim.g.autoformat = false
vim.o.clipboard = "unnamedplus"

-- Over SSH there's no native system clipboard, so route copy through OSC 52
-- escape sequences (terminal must support it). Locally we keep the native
-- `unnamedplus` clipboard set above, which works on Windows/Linux/macOS.
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
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
end
