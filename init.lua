-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
vim.g.autoformat = false
vim.o.clipboard = "unnamedplus"

-- Over SSH, or when no native clipboard tool is installed (e.g. a container),
-- route copy through OSC 52 escape sequences (terminal must support it).
-- Otherwise we keep the native `unnamedplus` clipboard set above.
local function has_native_clipboard()
  for _, exe in ipairs({ "wl-copy", "xclip", "xsel", "win32yank.exe", "clip.exe", "pbcopy" }) do
    if vim.fn.executable(exe) == 1 then
      return true
    end
  end
  return false
end

if vim.env.SSH_TTY or vim.env.SSH_CONNECTION or not has_native_clipboard() then
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
