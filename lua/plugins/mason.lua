--if true then return {} end
return {
  "mason-org/mason.nvim",
  opts = {
    -- Keep paths short on Windows: under nvim-data, Roslyn's BuildHost-net472 exe ends up
    -- past MAX_PATH (260), so it can't be started and .NET Framework csproj files never
    -- load (gd, references etc. break). It also must be a real folder, not a junction:
    -- .NET Framework then treats the build host as a "network location" and refuses to load it.
    install_root_dir = vim.fn.has("win32") == 1 and "C:/mason" or nil,
    -- Add the custom registry
    registries = {
        "github:Crashdummyy/mason-registry", -- Custom registry
        "github:mason-org/mason-registry",
    },
  },
}
