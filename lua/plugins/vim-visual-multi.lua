
return {
  -- Add the vim-visual-multi plugin to your lazy load plugins list
  {
    'mg979/vim-visual-multi',
    branch = 'master',
    config = function()
      -- Custom configuration if needed
      -- Set default mappings for visual multi plugin
      vim.g.vm_keymap_prefix = '<C-n>'  -- Default is Ctrl+n for starting multi-cursor

      -- You can also configure other key mappings or behavior here.
    end,
  },
}
