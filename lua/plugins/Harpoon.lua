
-- basic telescope configuration
local conf = require("telescope.config").values
local function toggle_telescope(harpoon_files)
    local file_paths = {}
    for _, item in ipairs(harpoon_files.items) do
        table.insert(file_paths, item.value)
    end

    require("telescope.pickers").new({}, {
        prompt_title = "Harpoon",
        finder = require("telescope.finders").new_table({
            results = file_paths,
        }),
        previewer = conf.file_previewer({}),
        sorter = conf.generic_sorter({}),
    }):find()
end

return {
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim",
      init = function()
        local harpoon = require('harpoon')
        local wk = require("which-key") 
        
        vim.keymap.set("n", "<leader>a", function() harpoon:list():append() end, {desc = "Add to harpoon"})
        vim.keymap.set("n", "<C-e>", function() toggle_telescope(harpoon:list()) end, { desc = "Open harpoon window" })
        vim.keymap.set("n", "<C-M-c>", function() harpoon:list():clear() end, { desc = "Clear harpoon list" })
        vim.keymap.set("n", "<C-M-Q>", function() harpoon:list():select(2) end, { desc = "Select Harpoon list 1" })
        vim.keymap.set("n", "<C-M-W>", function() harpoon:list():select(2) end, { desc = "Select Harpoon list 2" })
        vim.keymap.set("n", "<C-M-E>", function() harpoon:list():select(3) end, { desc = "Select Harpoon list 3" })
        vim.keymap.set("n", "<C-M-R>", function() harpoon:list():select(4) end, { desc = "Select Harpoon list 4" })

        -- Toggle previous & next buffers stored within Harpoon list
        vim.keymap.set("n", "<C-M-P>", function() harpoon:list():prev() end, { desc = "Select previous buffer in Harpoon list" })
        vim.keymap.set("n", "<C-M-N>", function() harpoon:list():next() end, { desc = "Select next buffer in Harpoon list" })
      end
       
    },
  },
}
