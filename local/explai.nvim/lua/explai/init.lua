-- Explai: explain code, ask about it, trace its callers and find implementations,
-- in a floating window next to the code, using GitHub Copilot.
local M = {}

M.config = {
  model = "claude-sonnet-5.5", -- any id from :ExplaiModel
  word_count = 60, -- length of the short explanation
  context_lines = 20, -- surrounding lines sent along as context
  max_width = 90,
  max_height = 25,
  border = "rounded",
}

local state_file = vim.fn.stdpath("data") .. "/explai.json"

local function load_state()
  local ok, lines = pcall(vim.fn.readfile, state_file)
  local data = ok and require("explai.util").decode(table.concat(lines, "\n")) or nil
  return type(data) == "table" and data or {}
end

local function save_state(data)
  pcall(vim.fn.writefile, { vim.json.encode(data) }, state_file)
end

local function set_model(id)
  M.config.model = id
  local s = load_state()
  s.model = id
  save_state(s)
  vim.notify("Explai: using " .. id, vim.log.levels.INFO)
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  local saved = load_state().model
  if saved then
    M.config.model = saved
  end

  local ui = require("explai.ui")
  ui.setup_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("explai_hl", { clear = true }),
    callback = ui.setup_highlights,
  })

  local cmd = vim.api.nvim_create_user_command

  cmd("Explai", function(o)
    local explain = require("explai.explain")
    explain.run(explain.selection(o), o.bang)
  end, { range = true, bang = true, desc = "Explai: explain the selection or current line (! = detailed)" })

  cmd("ExplaiAsk", function(o)
    local explain = require("explai.explain")
    local sel = explain.selection(o)
    local function go(q)
      if q and vim.trim(q) ~= "" then
        explain.run(sel, o.bang, vim.trim(q))
      end
    end
    if o.args ~= "" then
      go(o.args)
    else
      vim.ui.input({ prompt = "Ask Explai: " }, go)
    end
  end, { range = true, bang = true, nargs = "*", desc = "Explai: ask a question about the selection" })

  cmd("ExplaiFind", function(o)
    require("explai.find").run(o.args)
  end, { nargs = "*", desc = "Explai: find where something is implemented" })

  cmd("ExplaiCallers", function(o)
    require("explai.callers").run(o.args)
  end, { nargs = "*", desc = "Explai: trace how the function at the cursor is reached" })

  cmd("ExplaiLast", function()
    ui.reopen()
  end, { desc = "Explai: show the last result again" })

  cmd("ExplaiClose", function()
    ui.close()
  end, { desc = "Explai: close the popup" })

  cmd("ExplaiModel", function(o)
    if o.args ~= "" then
      return set_model(o.args)
    end
    require("explai.copilot").models(function(err, models)
      if err then
        return vim.notify("Explai: " .. err, vim.log.levels.ERROR)
      end
      vim.ui.select(models, {
        prompt = "Explai model (current: " .. M.config.model .. ")",
        format_item = function(m)
          return (m.id == M.config.model and "● " or "  ") .. m.name .. "  (" .. m.id .. ")"
        end,
      }, function(choice)
        if choice then
          set_model(choice.id)
        end
      end)
    end)
  end, { nargs = "?", desc = "Explai: choose the Copilot model" })
end

return M
