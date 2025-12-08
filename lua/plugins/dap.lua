if true then return {} end
return {
    "mfussenegger/nvim-dap",
    dependencies = {
        "nvim-telescope/telescope.nvim",
    },
    opts = function(_, _)
        local dap = require("dap")
        local pickers = require("telescope.pickers")
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        local function pick_exe(callback)
            local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
            local fd_cmd = { "fd", "--type", "f", "--extension", "exe", "--no-ignore", ".", git_root }

            local handle = io.popen(table.concat(fd_cmd, " "))
            if not handle then
                vim.notify("Failed to run fd", vim.log.levels.ERROR)
                return
            end

            local output = handle:read("*a")
            handle:close()

            local results = {}
            for line in output:gmatch("[^\r\n]+") do
                table.insert(results, line)
            end

            pickers
                .new({}, {
                    prompt_title = "Select .NET EXE",
                    finder = finders.new_table({ results = results }),
                    sorter = conf.generic_sorter({}),
                    attach_mappings = function(_, map)
                        actions.select_default:replace(function()
                            actions.close(_)
                            local selection = action_state.get_selected_entry()
                            callback(selection[1])
                        end)
                        return true
                    end,
                })
                :find()
        end

        dap.adapters.coreclr = {
            type = "executable",
            command = "netcoredbg",
            args = { "--interpreter=vscode" },
        }

        -- GDB adapter for remote debugging
        dap.adapters.gdb = {
            type = "executable",
            command = "gdb",
            args = { "--eval-command", "set print pretty on" },
        }

        -- -- CPPDBG adapter for C/C++ debugging
        -- dap.adapters.cppdbg = {
        --     id = "cppdbg",
        --     type = "executable",
        --     command = "/home/fjc/.vscode/extensions/ms-vscode.cpptools-1.22.11-linux-x64/debugAdapters/bin/OpenDebugAD7",
        -- }

        dap.configurations.cs = {
            {
                type = "coreclr",
                name = "Launch .NET EXE (Telescope)",
                request = "launch",
                program = function()
                    return coroutine.create(function(coro)
                        pick_exe(function(path)
                            coroutine.resume(coro, path)
                        end)
                    end)
                end,
            },
        }

        dap.configurations.cpp = {
            {
                name = "Launch remote gdbserver UP2210V3",
                type = "cppdbg",
                request = "launch",
                program = function()
                    return vim.fn.getcwd() .. "/build/UP2210V3.out"
                end,
                args = {},
                stopOnEntry = false,
                cwd = vim.fn.getcwd(),
                environment = {},
                externalConsole = false,
                MIMode = "gdb",
                miDebuggerPath = "/usr/bin/gdb-multiarch",
                preLaunchTask = "start-remote-gdbserver",
                miDebuggerServerAddress = "10.10.11.126:1234",
                setupCommands = {
                    {
                        description = "Enable pretty-printing for gdb",
                        text = "-enable-pretty-printing",
                        ignoreFailures = true,
                    },
                    {
                        description = "Set disassembly flavor to Intel",
                        text = "-gdb-set disassembly-flavor intel",
                        ignoreFailures = true,
                    },
                },
                console = "integratedTerminal", -- Forward terminal output to Neovim terminal
            },
            {
                name = "(gdb) Launch local",
                type = "cppdbg",
                request = "launch",
                program = vim.fn.getcwd() .. "/build/UP2210V3.out",
                args = {},
                stopOnEntry = false,
                cwd = vim.fn.expand('%:p:h'),
                environment = {},
                externalConsole = false,
                MIMode = "gdb",
                setupCommands = {
                    {
                        description = "Enable pretty-printing for gdb",
                        text = "-enable-pretty-printing",
                        ignoreFailures = true,
                    },
                    {
                        description = "Set Disassembly Flavor to Intel",
                        text = "-gdb-set disassembly-flavor intel",
                        ignoreFailures = true,
                    },
                },
            },
        }

        -- Use same config for C
        dap.configurations.c = dap.configurations.cpp
    end,
}
