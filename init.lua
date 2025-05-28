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

-- Define the function to search with rga (ripgrep) using Snacks picker
function Snacks_rga()
    require("snacks").picker.pick({
        cmd = "rga", -- Using ripgrep as the search tool
        args = { "--json" }, -- Using JSON output
        prompt_title = "Search with rga", -- Title for the search prompt
        search_dirs = { vim.fn.expand("%:p:h") }, -- Search in the current file's directory
        query_on_input = true, -- Keep the query live as you type
        default_query = "", -- Start with an empty search query
        live_args = function(query)
            return { "--json", query } -- Dynamically update the query for each search
        end,
        format = function(entry)
            -- Add debugging to check entry value
            if not entry then
                return ""
            end
            -- Check if entry.text is available
            if entry.text then
                return entry.text
            else
                -- Log entry for debugging
                print(vim.inspect(entry)) -- This will log the entry structure to help debug
                return "" -- Return empty if no valid text is found
            end
        end,
    })
end

-- Keybinding to call the Snacks_rga function (Search with rga)
vim.api.nvim_set_keymap(
    "n",
    "<leader>gr",
    [[<Cmd>lua Snacks_rga()<CR>]],
    { noremap = true, silent = true, desc = "Search with rga" }
)
