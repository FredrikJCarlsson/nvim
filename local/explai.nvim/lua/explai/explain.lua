-- Explain the selection (or current line), or answer a question about it, streamed
-- into the floating window next to the code.
local copilot = require("explai.copilot")
local ui = require("explai.ui")
local util = require("explai.util")

local M = {}
local api = vim.api

--- Finished answers, so explaining the same unchanged code again is instant.
local cache = {} ---@type table<string, table>
local cache_order = {} ---@type string[]
local CACHE_SIZE = 30

local SYSTEM = "You are Explai, a code explanation assistant inside Neovim. The reader is an experienced "
  .. "developer who is new to this codebase. Be concise, concrete and accurate; never invent behaviour "
  .. "that is not visible in the code you are given."

local function cfg()
  return require("explai").config
end

--- The code to explain, from a command's range (visual selection) or the current line.
---@param opts {range: integer, line1: integer, line2: integer}
function M.selection(opts)
  local buf = api.nvim_get_current_buf()
  local first, last = opts.line1 - 1, opts.line2 - 1
  local text
  if opts.range == 0 then
    first = api.nvim_win_get_cursor(0)[1] - 1
    last = first
    text = util.trim(api.nvim_buf_get_lines(buf, first, first + 1, false)[1] or "")
  else
    local s, e = api.nvim_buf_get_mark(buf, "<"), api.nvim_buf_get_mark(buf, ">")
    if first == last and vim.fn.visualmode() == "v" and s[1] == opts.line1 and e[1] == opts.line2 then
      -- Characterwise selection on one line: just the selected part.
      local line = api.nvim_buf_get_lines(buf, first, first + 1, false)[1] or ""
      text = line:sub(s[2] + 1, math.min(e[2] + 1, #line))
    else
      text = table.concat(api.nvim_buf_get_lines(buf, first, last + 1, false), "\n")
    end
  end
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
  return {
    buf = buf,
    win = api.nvim_get_current_win(),
    first = first,
    last = last,
    text = text,
    where = ("%s:%s"):format(name ~= "" and name or "[No Name]", first == last and first + 1 or ("%d–%d"):format(first + 1, last + 1)),
  }
end

local function key_for(sel, detailed, question)
  return table.concat({
    sel.buf,
    api.nvim_buf_get_changedtick(sel.buf),
    sel.first,
    sel.last,
    #sel.text,
    detailed and 1 or 0,
    question or "",
  }, "|")
end

local function remember(key, view)
  if not cache[key] then
    table.insert(cache_order, key)
    if #cache_order > CACHE_SIZE then
      cache[table.remove(cache_order, 1)] = nil
    end
  end
  cache[key] = view
end

local function build_prompt(sel, detailed, question)
  local buf = sel.buf
  local lang = vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype or "text"
  local root = util.root(buf)
  local file = util.rel(api.nvim_buf_get_name(buf), root)
  local n = cfg().context_lines
  local before = api.nvim_buf_get_lines(buf, math.max(0, sel.first - n), sel.first, false)
  local after = api.nvim_buf_get_lines(buf, sel.last + 1, sel.last + 1 + n, false)
  local bullets = detailed and "3-7" or (question and "1-4" or "2-3")
  local words = detailed and 250 or (question and 100 or cfg().word_count)

  local task, first_line, section
  if question then
    task = ('Answer this question about the %s code below from %s: "%s". If the code shown is not '
      .. "enough to answer with certainty, say so and say what you would need to check."):format(lang, file, question)
    first_line = "**<the direct answer, one or two sentences>**"
    section = "**Why**"
  else
    task = ("Explain what the %s code below from %s does and why."):format(lang, file)
    first_line = "**<one sentence: what the code does>**"
    section = "**How it works**"
  end

  return table.concat({
    task,
    ("Use about %d words in total. Format the answer as Markdown exactly like this:"):format(words),
    "",
    first_line,
    "",
    section,
    ("- <%s short bullets>"):format(bullets),
    "",
    "**⚠ Watch out**",
    "- <only if there are real pitfalls: bugs, edge cases, side effects, performance; omit this whole section otherwise>",
    "",
    "Wrap identifiers in `backticks`. No other headings, no preamble, do not restate the code.",
    "",
    "Code:",
    "```" .. lang,
    sel.text,
    "```",
    "",
    "Surrounding code, for context only:",
    "```" .. lang,
    table.concat(before, "\n"),
    "/* ...the code above... */",
    table.concat(after, "\n"),
    "```",
  }, "\n")
end

--- Explain `sel` (from M.selection), or answer `question` about it.
function M.run(sel, detailed, question)
  local key = key_for(sel, detailed, question)

  -- Same request while its popup is open: jump into the popup (like pressing K twice).
  if ui.current_id() == key and not ui.is_loading() then
    return ui.focus()
  end
  local cached = cache[key]
  if cached then
    cached.anchor.win = sel.win
    return ui.show(cached)
  end

  local model = cfg().model
  local kind = question and ("“" .. util.truncate(question, 50) .. "”") or (detailed and "Detailed" or nil)
  local view = {
    id = key,
    kind = kind,
    where = sel.where,
    anchor = { buf = sel.buf, win = sel.win, row = sel.last },
    highlight = { buf = sel.buf, first = sel.first, last = sel.last },
    loading = true,
    lines = { "_Asking " .. model .. "…_" },
    hints = "q cancel",
    keys = {
      m = function()
        if detailed then
          return
        end
        ui.close()
        if api.nvim_win_is_valid(sel.win) then
          api.nvim_set_current_win(sel.win)
        end
        M.run(sel, true, question)
      end,
    },
  }

  local chunks = {}
  local started = vim.uv.hrtime()
  local cancel
  view.on_cancel = function()
    if cancel then
      cancel()
    end
  end
  ui.show(view)

  cancel = copilot.stream({
    model = model,
    temperature = 0.2,
    messages = {
      { role = "system", content = SYSTEM },
      { role = "user", content = build_prompt(sel, detailed, question) },
    },
  }, function(delta)
    table.insert(chunks, delta)
    if ui.current_id() == key then
      view.lines = vim.split(table.concat(chunks), "\n")
      ui.show(view)
    end
  end, function(err)
    view.loading = false
    local secs = (vim.uv.hrtime() - started) / 1e9
    if err then
      view.lines = { "**Request failed**", "", err }
      view.hints = "q close"
    else
      local text = util.trim(table.concat(chunks))
      view.lines = vim.split(text ~= "" and text or "_No response._", "\n")
      view.plain = text
      view.hints = (detailed and "" or "m more · ") .. "y copy · o open · q close"
      view.meta = ("%s · %.1fs"):format(model, secs)
      remember(key, view)
    end
    if ui.current_id() == key then
      ui.show(view)
    elseif not err then
      ui.remember(view)
    end
  end)
end

return M
