--if true then return {} end
return {
  "mason-org/mason.nvim",
  opts = {
    -- Add the custom registry
    registries = {
        "github:Crashdummyy/mason-registry", -- Custom registry
        "github:mason-org/mason-registry",
    },
  },
}
