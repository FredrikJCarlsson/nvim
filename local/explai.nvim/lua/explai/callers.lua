-- Trace Callers: how is the function at the cursor reached? Builds the incoming call tree
-- from the language server, lets the model fill gaps with the tools, and shows 1-3 call
-- paths (entry point → target). <CR> on a step jumps there; steps also go to quickfix.
local tools = require("explai.tools")
local ui = require("explai.ui")
local util = require("explai.util")

local M = {}
local api = vim.api

local TREE_DEPTH = 4
local TREE_MAX_NODES = 30
local PREPARE = "textDocument/prepareCallHierarchy"

-- LSP SymbolKind: Method, Property, Constructor, Function, Operator
local FUNCTION_KINDS = { [6] = true, [7] = true, [9] = true, [12] = true, [25] = true }

local REPORT = {
  type = "function",
  ["function"] = {
    name = "report_flow",
    description = "Finish: report how the target is reached. Give 1-3 distinct call paths, each ordered from the "
      .. "entry point (UI event, Main, API endpoint, timer, thread start, test…) down to the target itself as the "
      .. "last step. Paths and line numbers must be verified with the tools.",
    parameters = {
      type = "object",
      properties = {
        summary = { type = "string", description = "One or two sentences: who triggers the target and why" },
        paths = {
          type = "array",
          items = {
            type = "object",
            properties = {
              title = { type = "string", description = 'Short name for the path, e.g. "Manual import from the UI"' },
              steps = {
                type = "array",
                items = {
                  type = "object",
                  properties = {
                    name = { type = "string", description = 'Function/method, e.g. "ImportService.Run"' },
                    path = { type = "string" },
                    line = { type = "number", description = "1-based line of the call (declaration for the entry point)" },
                    description = { type = "string", description = "What happens at this step, max ~15 words" },
                  },
                  required = { "name", "path", "line", "description" },
                },
              },
            },
            required = { "title", "steps" },
          },
        },
        notes = {
          type = "array",
          items = { type = "string" },
          description = "0-3 notable things: conditions that gate the call, threading, error handling, dead paths",
        },
      },
      required = { "summary", "paths" },
    },
  },
}

local function contains(range, row, col)
  local s, e = range.start, range["end"]
  if row < s.line or row > e.line then
    return false
  end
  if row == s.line and col < s.character then
    return false
  end
  if row == e.line and col > e.character then
    return false
  end
  return true
end

local function innermost(symbols, row, col)
  local best
  local function visit(list)
    for _, s in ipairs(list or {}) do
      local range = s.range or (s.location and s.location.range)
      if range and contains(range, row, col) then
        if FUNCTION_KINDS[s.kind] then
          best = { name = s.name, range = range, pos = (s.selectionRange or range).start }
        end
        visit(s.children)
      end
    end
  end
  visit(symbols)
  return best
end

--- Function at/around the cursor: {name, row, item?, body_first, body_last}
local function find_target(buf, win)
  local cursor = api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]
  local uri = vim.uri_from_bufnr(buf)

  local function prepare_at(r, c)
    local results = tools.request(buf, PREPARE, function(client)
      local line = api.nvim_buf_get_lines(buf, r, r + 1, false)[1] or ""
      local character = c
      if client.offset_encoding ~= "utf-8" then
        character = vim.str_utfindex(line, client.offset_encoding, math.min(c, #line), false)
      end
      return { textDocument = { uri = uri }, position = { line = r, character = character } }
    end)
    return results[1] and results[1][1] or nil
  end

  -- 1. Identifier under the cursor that is a function declared in this file.
  local at_cursor = prepare_at(row, col)
  if at_cursor and at_cursor.uri == uri then
    return {
      name = at_cursor.name,
      row = at_cursor.selectionRange.start.line,
      item = at_cursor,
      first = at_cursor.range.start.line,
      last = at_cursor.range["end"].line,
    }
  end

  -- 2. Innermost function/method containing the cursor.
  local symbols = tools.request(buf, "textDocument/documentSymbol", { textDocument = { uri = uri } })
  local enclosing = symbols[1] and innermost(symbols[1], row, col)
  if enclosing then
    return {
      name = enclosing.name,
      row = enclosing.pos.line,
      item = prepare_at(enclosing.pos.line, enclosing.pos.character),
      first = enclosing.range.start.line,
      last = enclosing.range["end"].line,
    }
  end

  -- 3. A call to a function in another file: the call tree still works.
  if at_cursor then
    return { name = at_cursor.name, row = row, item = at_cursor, first = row, last = row }
  end

  -- 4. No language server: go by the word under the cursor and let the model search.
  local word = vim.fn.expand("<cword>")
  if word ~= "" then
    return { name = word, row = row, first = row, last = row }
  end
end

local function call_tree(buf, root_item, root)
  local lines = { ("%s — %s:%d"):format(root_item.name, util.rel(vim.uri_to_fname(root_item.uri), root), root_item.selectionRange.start.line + 1) }
  local seen, count = {}, 0
  local function key(item)
    return item.uri .. "#" .. item.selectionRange.start.line .. ":" .. item.selectionRange.start.character
  end
  seen[key(root_item)] = true

  local function walk(item, depth, indent)
    local calls = tools.incoming_calls(buf, item)
    if #calls == 0 and depth == TREE_DEPTH then
      table.insert(lines, indent .. "(no callers found by the language server)")
    end
    for i, c in ipairs(calls) do
      if i > 8 then
        table.insert(lines, ("%s… %d more callers"):format(indent, #calls - 8))
        break
      end
      if count >= TREE_MAX_NODES then
        table.insert(lines, indent .. "… (tree truncated)")
        return
      end
      count = count + 1
      local sites = {}
      for j, r in ipairs(c.fromRanges or {}) do
        if j > 3 then
          break
        end
        table.insert(sites, r.start.line + 1)
      end
      local k = key(c.from)
      table.insert(lines, ("%s← %s%s — %s:%d, call at line %s%s"):format(
        indent,
        c.from.name,
        c.from.detail and c.from.detail ~= "" and (" (" .. c.from.detail .. ")") or "",
        util.rel(vim.uri_to_fname(c.from.uri), root),
        c.from.selectionRange.start.line + 1,
        table.concat(sites, ", "),
        seen[k] and " [already shown above]" or ""
      ))
      if not seen[k] then
        seen[k] = true
        if depth > 1 then
          walk(c.from, depth - 1, indent .. "    ")
        end
      end
    end
  end

  walk(root_item, TREE_DEPTH, "    ")
  return table.concat(lines, "\n")
end

local function render(flow, target, root, focus, model, secs)
  local lines, links, doc, qf = {}, {}, {}, {}
  local function add(l)
    table.insert(lines, l)
  end

  table.insert(doc, ("# How `%s` is reached"):format(target.name))
  table.insert(doc, "")
  if focus ~= "" then
    add("_“" .. util.truncate(focus, 90) .. "”_")
    add("")
    table.insert(doc, "> " .. focus)
    table.insert(doc, "")
  end
  if flow.summary ~= "" then
    add("**" .. flow.summary:gsub("%*%*", "") .. "**")
    add("")
    table.insert(doc, "**" .. flow.summary .. "**")
    table.insert(doc, "")
  end

  for _, p in ipairs(flow.paths) do
    add("**▶ " .. p.title .. "**")
    table.insert(doc, "## " .. p.title)
    table.insert(doc, "")
    for i, s in ipairs(p.steps) do
      local abs = util.resolve(s.path, root)
      local short = vim.fn.fnamemodify(s.path, ":t") .. ":" .. s.line
      local name = i == #p.steps and ("**`" .. s.name .. "`**") or ("`" .. s.name .. "`")
      add(("%d. %s — %s  _%s_"):format(i, name, s.description, short))
      if abs then
        links[#lines] = { path = abs, line = s.line }
        table.insert(qf, { filename = abs, lnum = s.line, text = p.title .. " · " .. i .. ". " .. s.name .. " — " .. s.description })
      end
      -- path:line so `gF` jumps there from the document
      table.insert(doc, ("%d. `%s` — %s (%s:%d)"):format(i, s.name, s.description, abs and util.rel(abs, root) or s.path, s.line))
    end
    add("")
    table.insert(doc, "")
  end

  if #flow.notes > 0 then
    add("**ℹ Notes**")
    table.insert(doc, "## Notes")
    table.insert(doc, "")
    for _, n in ipairs(flow.notes) do
      add("- " .. n)
      table.insert(doc, "- " .. n)
    end
  end
  while lines[#lines] == "" do
    table.remove(lines)
  end

  return {
    lines = lines,
    links = links,
    document = doc,
    plain = table.concat(doc, "\n"),
    qf = qf,
    meta = ("%s · %.1fs"):format(model, secs),
  }
end

local function normalize(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local flow = { summary = type(raw.summary) == "string" and util.trim(raw.summary) or "", paths = {}, notes = {} }
  for _, p in ipairs(type(raw.paths) == "table" and raw.paths or {}) do
    if type(p) == "table" and #flow.paths < 3 then
      local steps = {}
      for _, s in ipairs(type(p.steps) == "table" and p.steps or {}) do
        if type(s) == "table" then
          table.insert(steps, {
            name = tostring(s.name or "?"),
            path = tostring(s.path or ""),
            line = math.max(1, math.floor(tonumber(s.line) or 1)),
            description = tostring(s.description or ""),
          })
        end
      end
      if #steps > 0 then
        table.insert(flow.paths, { title = tostring(p.title or "Call path"), steps = steps })
      end
    end
  end
  for _, n in ipairs(type(raw.notes) == "table" and raw.notes or {}) do
    if type(n) == "string" and n ~= "" and #flow.notes < 3 then
      table.insert(flow.notes, n)
    end
  end
  if flow.summary == "" and #flow.paths == 0 then
    return nil
  end
  return flow
end

function M.run(focus)
  focus = util.trim(focus or "")
  util.run(function()
    local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
    local root = util.root(buf)
    local model = require("explai").config.model
    local ctx = { buf = buf, root = root, cancelled = false }
    local id = "callers:" .. vim.uv.hrtime()
    ctx.status = function(text)
      ui.status(id, text)
    end

    local view = {
      id = id,
      kind = "Callers",
      where = vim.fn.expand("<cword>"),
      anchor = { buf = buf, win = win, row = api.nvim_win_get_cursor(win)[1] - 1 },
      loading = true,
      lines = { "_Finding the function…_" },
      hints = "q cancel",
      on_cancel = function()
        ctx.cancelled = true
        if ctx.cancel then
          ctx.cancel()
        end
      end,
    }
    ui.show(view)
    local started = vim.uv.hrtime()

    local target = find_target(buf, win)
    if ctx.cancelled then
      return
    end
    if not target then
      ui.close()
      return vim.notify("Explai: put the cursor on or inside a function.", vim.log.levels.INFO)
    end
    view.where = target.name
    ctx.status("Building call tree")
    local tree = target.item and call_tree(buf, target.item, root) or ""
    if ctx.cancelled then
      return
    end

    local lang = vim.bo[buf].filetype
    local last = math.min(target.last, target.first + 100)
    local code = table.concat(api.nvim_buf_get_lines(buf, target.first, last + 1, false), "\n")
    local file = util.rel(api.nvim_buf_get_name(buf), root)

    local prompt = table.concat({
      ("Explain how the function `%s` (%s:%d) is reached: trace its callers up to the real entry points "
        .. "(UI event handlers, Main, API/RPC endpoints, timers, background threads/tasks, scheduled jobs, tests)."):format(
        target.name, file, target.row + 1),
      "",
      tree ~= "" and ("Incoming call tree from the language server (may be incomplete: it misses calls through "
        .. "interfaces, delegates/events, reflection, DI, virtual dispatch and other languages):\n" .. tree)
        or "No call hierarchy is available from the language server; use find_references and search_text.",
      "",
      "Use the tools to fill gaps (find_callers on callers that weren't expanded; find_references or search_text "
        .. "for interface implementations, event subscriptions (+=), delegates, registrations) and read_file to verify "
        .. "the call sites and the conditions around them. Skip tests unless they are the only callers. "
        .. "Finish by calling report_flow exactly once.",
      focus ~= "" and ("\nThe user specifically wants to know: " .. focus) or "",
      "",
      "Target code:",
      "```" .. lang,
      util.truncate(code, 6000),
      "```",
    }, "\n")

    local result, err = tools.agent(ctx, {
      {
        role = "system",
        content = "You are a code navigation assistant inside Neovim (project root: " .. root .. "). Be precise and verify with the tools.",
      },
      { role = "user", content = prompt },
    }, REPORT)
    if ctx.cancelled then
      return
    end

    local flow = result and normalize(result)
    if not flow then
      ui.close()
      return vim.notify("Explai: " .. (err and tostring(err) or ("couldn't work out how " .. target.name .. " is reached.")), vim.log.levels.WARN)
    end

    local out = render(flow, target, root, focus, model, (vim.uv.hrtime() - started) / 1e9)
    if #out.qf > 0 then
      vim.fn.setqflist({}, " ", { title = "Explai: callers of " .. target.name, items = out.qf })
    end
    view.loading = false
    view.anchor = { buf = buf, win = win, row = target.row }
    view.lines = out.lines
    view.links = out.links
    view.document = out.document
    view.plain = out.plain
    view.meta = out.meta
    view.hints = "⏎ jump · o open · y copy · q close"
    if ui.current_id() == id then
      ui.show(view)
    else
      ui.remember(view)
      vim.notify("Explai: call trace ready, <leader>al to show it.", vim.log.levels.INFO)
    end
  end)
end

return M
