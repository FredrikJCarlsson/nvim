-- return {
--   -- Add Telescope plugin
--   {
--     'nvim-telescope/telescope.nvim',
--     dependencies = { 'nvim-lua/plenary.nvim' },
--   },
-- }
-- in your lazyvim config or a separate plugin config file
require('snacs').setup({
  telescope = {
    defaults = {
      hidden = true,    -- include hidden files
      no_ignore = true, -- include .gitignored files
    },
  },
})
