-- Find Implementation: describe something, the model searches the project with the
-- read-only tools, then Explai jumps to the best match and shows why it was picked.
-- All matches also go to the quickfix list (]q / [q).
local tools = require("explai.tools")
local ui = require("explai.ui")
local util = require("explai.util")

local M = {}
local api = vim.api

local REPORT = {
  type = "function",
  ["function"] = {
    name = "report_results",
    description = "Finish: report where the requested thing is implemented, best match first (1-5 results). "
      .. "Line numbers must cover the actual implementation (e.g. the whole method), verified with read_file.",
    parameters = {
      type = "object",
      properties = {
        results = {
          type = "array",
          items = {
            type = "object",
            properties = {
              path = { type = "string" },
              startLine = { type = "number" },
              endLine = { type = "number" },
              title = { type = "string", description = 'Short label, e.g. "ImportService.InsertBlocks"' },
              reason = { type = "string", description = "One or two sentences: why this is the place / what it does" },
            },
            required = { "path", "startLine", "endLine", "title", "reason" },
          },
        },
      },
      required = { "results" },
    },
  },
}

local function show_result(r, query, all)
  local win = api.nvim_get_current_win()
  vim.cmd("normal! m'")
  vim.cmd.edit(vim.fn.fnameescape(r.abs))
  local buf = api.nvim_get_current_buf()
  local count = api.nvim_buf_line_count(buf)
  local first, last = math.min(r.startLine, count) - 1, math.min(r.endLine, count) - 1
  api.nvim_win_set_cursor(win, { first + 1, 0 })
  vim.cmd("normal! ^zt")
  if first > 0 then
    vim.cmd("normal! " .. math.min(5, first) .. "\25") -- a little context above (<C-y>)
  end

  local others = #all - 1
  local name = vim.fn.fnamemodify(r.abs, ":t")
  ui.show({
    id = "find:" .. r.abs .. ":" .. first,
    kind = "Found",
    where = ("%s:%s"):format(name, first == last and first + 1 or ("%d–%d"):format(first + 1, last + 1)),
    anchor = { buf = buf, win = win, row = first },
    prefer = "above",
    highlight = { buf = buf, first = first, last = last },
    lines = {
      "**" .. r.title:gsub("%*%*", "") .. "**",
      "",
      r.reason,
      "",
      "_You asked: " .. util.truncate(query, 100) .. "_",
    },
    plain = r.title .. "\n" .. r.reason,
    hints = (others > 0 and (("]q %d other match%s · "):format(others, others > 1 and "es" or "")) or "")
      .. "e explain · q close",
    meta = require("explai").config.model,
    keys = {
      e = function()
        ui.close()
        api.nvim_set_current_win(win)
        require("explai.explain").run({
          buf = buf,
          win = win,
          first = first,
          last = last,
          text = table.concat(api.nvim_buf_get_lines(buf, first, last + 1, false), "\n"),
          where = ("%s:%d–%d"):format(name, first + 1, last + 1),
        }, false)
      end,
    },
  })
end

function M.run(query)
  util.run(function()
    if not query or util.trim(query) == "" then
      query = util.await(function(cb)
        vim.ui.input({ prompt = "Explai – find implementation of: " }, cb)
      end)
      if not query or util.trim(query) == "" then
        return
      end
    end

    local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
    local root = util.root(buf)
    local ctx = { buf = buf, root = root, cancelled = false }
    local id = "find-progress:" .. vim.uv.hrtime()
    ctx.status = function(text)
      ui.status(id, text)
    end

    local context = ""
    local file = api.nvim_buf_get_name(buf)
    if file ~= "" then
      context = "\nThe user currently has " .. util.rel(file, root) .. " open.\n"
    end

    ui.show({
      id = id,
      kind = "Find",
      where = util.truncate(query, 50),
      anchor = { buf = buf, win = win, row = api.nvim_win_get_cursor(win)[1] - 1 },
      loading = true,
      lines = { "_Searching…_" },
      hints = "q cancel",
      on_cancel = function()
        ctx.cancelled = true
        if ctx.cancel then
          ctx.cancel()
        end
      end,
    })

    local result, err = tools.agent(ctx, {
      {
        role = "system",
        content = "You are a code navigation assistant inside Neovim. Find where things are implemented in the "
          .. "user's project (root: " .. root .. ") using the tools. Search efficiently: start with search_symbols "
          .. "and search_text, try synonyms and naming conventions, then read_file to confirm before answering. "
          .. "Prefer the actual implementation over interfaces, tests, call sites or comments, unless asked for "
          .. "those. Call report_results exactly once; with an empty list if nothing relevant exists.",
      },
      { role = "user", content = context .. "What I'm looking for: " .. query },
    }, REPORT)

    if ctx.cancelled then
      return
    end
    ui.close()
    if not result then
      return vim.notify("Explai: " .. tostring(err), vim.log.levels.ERROR)
    end

    local results = {}
    for _, r in ipairs(type(result.results) == "table" and result.results or {}) do
      local abs = type(r) == "table" and util.resolve(r.path, root)
      if abs and #results < 5 then
        local first = math.max(1, math.floor(tonumber(r.startLine) or 1))
        table.insert(results, {
          abs = abs,
          path = util.rel(abs, root),
          startLine = first,
          endLine = math.max(first, math.floor(tonumber(r.endLine) or first)),
          title = tostring(r.title or vim.fn.fnamemodify(abs, ":t")),
          reason = tostring(r.reason or ""),
        })
      end
    end
    if #results == 0 then
      return vim.notify(('Explai: couldn\'t find "%s" in the project.'):format(query), vim.log.levels.INFO)
    end

    local items = {}
    for _, r in ipairs(results) do
      table.insert(items, { filename = r.abs, lnum = r.startLine, end_lnum = r.endLine, text = r.title .. " — " .. r.reason })
    end
    vim.fn.setqflist({}, " ", { title = "Explai: " .. query, items = items })

    if api.nvim_win_is_valid(win) then
      api.nvim_set_current_win(win)
    end
    if #results == 1 then
      return show_result(results[1], query, results)
    end
    vim.ui.select(results, {
      prompt = "Explai: " .. util.truncate(query, 60),
      format_item = function(r)
        return ("%s  —  %s:%d"):format(r.title, r.path, r.startLine)
      end,
    }, function(choice)
      if choice then
        show_result(choice, query, results)
      end
    end)
  end)
end

return M
