return {
  "mfussenegger/nvim-dap",
  opts = {
    adapters = {
      lldb = {
        type = "executable",
        command = "lldb-vscode", -- Ensure lldb-vscode is in PATH
        name = "lldb",
      },
    },
    configurations = {
      swift = {
        name = "Launch",
        type = "lldb",
        request = "launch",
        program = function()
          return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
        args = {},
      },
    },
  },
}
