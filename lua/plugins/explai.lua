-- Explai: explain / ask about code, trace callers and find implementations with
-- GitHub Copilot, in a floating window next to the code. Local plugin in
-- local/explai.nvim. Uses the Copilot sign-in from copilot.lua.
return {
  dir = vim.fn.stdpath("config") .. "/local/explai.nvim",
  name = "explai.nvim",
  cond = not vim.g.vscode, -- in VS Code the Explai extension does this
  cmd = { "Explai", "ExplaiAsk", "ExplaiFind", "ExplaiCallers", "ExplaiLast", "ExplaiClose", "ExplaiModel" },
  keys = {
    { "<leader>ae", ":Explai<cr>", mode = { "n", "x" }, silent = true, desc = "Explai: Explain" },
    { "<leader>aE", ":Explai!<cr>", mode = { "n", "x" }, silent = true, desc = "Explai: Explain in detail" },
    -- Opens the command line so <Up> recalls earlier questions.
    { "<leader>aq", ":ExplaiAsk ", mode = { "n", "x" }, desc = "Explai: Ask about code" },
    { "<leader>ai", ":ExplaiFind ", desc = "Explai: Find implementation" },
    { "<leader>ak", "<cmd>ExplaiCallers<cr>", desc = "Explai: Trace callers" },
    { "<leader>al", "<cmd>ExplaiLast<cr>", desc = "Explai: Show last result" },
  },
  opts = {
    model = "claude-sonnet-5.5",
  },
}
