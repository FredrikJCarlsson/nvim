-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local keymap = vim.keymap

-- Inside VSCode/Cursor, LazyVim's LSP is disabled, so route LSP-style
-- keymaps to the editor's native commands instead.
if vim.g.vscode then
  local vscode = require("vscode")
  local function action(cmd)
    return function()
      vscode.action(cmd)
    end
  end

  keymap.set({ "n", "v" }, "<leader>cr", action("editor.action.rename"), { desc = "Rename Symbol" })
  keymap.set({ "n", "v" }, "<leader>ca", action("editor.action.quickFix"), { desc = "Code Action" })
  keymap.set("n", "<leader>cf", action("editor.action.formatDocument"), { desc = "Format Document" })
  keymap.set("n", "<leader>cd", action("editor.action.showHover"), { desc = "Show Hover" })

  -- Navigation
  keymap.set("n", "gd", action("editor.action.revealDefinition"), { desc = "Goto Definition" })
  keymap.set("n", "gD", action("editor.action.revealDeclaration"), { desc = "Goto Declaration" })
  keymap.set("n", "gr", action("editor.action.goToReferences"), { desc = "References" })
  keymap.set("n", "gI", action("editor.action.goToImplementation"), { desc = "Goto Implementation" })
  keymap.set("n", "gy", action("editor.action.goToTypeDefinition"), { desc = "Goto Type Definition" })

  -- Diagnostics
  keymap.set("n", "]d", action("editor.action.marker.next"), { desc = "Next Diagnostic" })
  keymap.set("n", "[d", action("editor.action.marker.prev"), { desc = "Prev Diagnostic" })

  -- Find / files (replaces Telescope/snacks picker, which is disabled in VSCode)
  keymap.set("n", "<leader>ff", action("workbench.action.quickOpen"), { desc = "Find Files" })
  keymap.set("n", "<leader><space>", action("workbench.action.quickOpen"), { desc = "Find Files" })
  keymap.set("n", "<leader>fr", action("workbench.action.openRecent"), { desc = "Recent Files" })
  keymap.set("n", "<leader>fn", action("explorer.newFile"), { desc = "New File" })
  keymap.set("n", "<leader>e", action("workbench.view.explorer"), { desc = "Explorer" })

  -- Search
  keymap.set("n", "<leader>sg", action("workbench.action.findInFiles"), { desc = "Grep (workspace)" })
  keymap.set("n", "<leader>/", action("workbench.action.findInFiles"), { desc = "Grep (workspace)" })
  keymap.set("n", "<leader>sw", action("workbench.action.findInFiles"), { desc = "Grep word under cursor" })
  keymap.set("n", "<leader>ss", action("workbench.action.gotoSymbol"), { desc = "Symbols (document)" })
  keymap.set("n", "<leader>sS", action("workbench.action.showAllSymbols"), { desc = "Symbols (workspace)" })
  keymap.set("n", "<leader>sd", action("workbench.actions.view.problems"), { desc = "Diagnostics" })
  keymap.set("n", "<leader>sk", action("workbench.action.openGlobalKeybindings"), { desc = "Keymaps" })
  keymap.set("n", "<leader>sc", action("workbench.action.showCommands"), { desc = "Commands" })

  -- Git
  keymap.set("n", "<leader>gg", action("workbench.view.scm"), { desc = "Source Control" })
  keymap.set("n", "<leader>gb", action("gitlens.toggleLineBlame"), { desc = "Line Blame" })

  -- Buffers / windows
  keymap.set("n", "<leader>bd", action("workbench.action.closeActiveEditor"), { desc = "Close Buffer" })
  keymap.set("n", "<leader>bo", action("workbench.action.closeOtherEditors"), { desc = "Close Other Buffers" })
end

-- Resize window
keymap.set("n", "<C-w><left>", "<C-w><")
keymap.set("n", "<C-w><right>", "<C-w>>")
keymap.set("n", "<C-w><up>", "<C-w>+")
keymap.set("n", "<C-w><down>", "<C-w>-")

-- Code Companion
-- vim.keymap.set({ "n" }, "<leader>at", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
-- vim.keymap.set({ "n", "v" }, "<leader>at", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
-- vim.keymap.set({ "n", "v" }, "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", { noremap = true, silent = true })
-- vim.keymap.set("v", "<leader>aa", "<cmd>CodeCompanionChat Add<cr>", { noremap = true, silent = true })

-- -- Git
-- vim.keymap.set("n", "<leader>gd", "<cmd>DiffviewOpen<cr>", { desc = "Open diffview" })
-- vim.keymap.set("n", "<leader>gq", "<cmd>DiffviewClose<cr>", { desc = "Close diffview" })
-- vim.keymap.set("n", "<leader>gh", "<cmd>DiffviewFileHistory<cr>", { desc = "Open branch history" })
-- vim.keymap.set("n", "<leader>gf", "<cmd>DiffviewFileHistory %<cr>", { desc = "Open file history" })
