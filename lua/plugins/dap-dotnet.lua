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
    end,
}
