-- Read-only workspace tools for the model (symbols, text search, files, call hierarchy,
-- references) and the tool-calling loop. Everything here runs inside util.run().
local copilot = require("explai.copilot")
local util = require("explai.util")

local M = {}
local api = vim.api
local await = util.await

local MAX_STEPS = 15
local MAX_OUTPUT = 6000

local function fn(name, description, properties, required)
  return {
    type = "function",
    ["function"] = {
      name = name,
      description = description,
      parameters = { type = "object", properties = properties, required = required },
    },
  }
end

local LOCATION = {
  path = { type = "string", description = "File path as returned by the other tools" },
  line = { type = "number", description = "1-based line where `name` appears" },
  name = { type = "string", description = "The identifier as written on that line" },
}

M.TOOLS = {
  fn(
    "search_symbols",
    "Search workspace symbols (classes, methods, functions, properties…) by name using the language servers. "
      .. "Fast and precise; try this first when you can guess an identifier name. Supports partial names.",
    { query = { type = "string", description = "Symbol name or part of it" } },
    { "query" }
  ),
  fn(
    "search_text",
    "Regex search over file contents in the project (ripgrep, respects .gitignore). Returns matching lines "
      .. "as path:line:text. Use for strings, table names, log messages, config keys, etc.",
    {
      pattern = { type = "string", description = "Regular expression (Rust regex syntax)" },
      glob = { type = "string", description = 'Optional glob to restrict the search, e.g. "*.cs"' },
      caseSensitive = { type = "boolean", description = "Default false (smart case)" },
    },
    { "pattern" }
  ),
  fn(
    "list_files",
    'List project files matching a glob, e.g. "**/*Import*.cs". Returns at most 100 paths.',
    { glob = { type = "string" } },
    { "glob" }
  ),
  fn(
    "read_file",
    "Read lines of a project file (1-based, inclusive, max 200 lines per call), prefixed with line numbers.",
    {
      path = { type = "string" },
      startLine = { type = "number" },
      endLine = { type = "number" },
    },
    { "path" }
  ),
  fn(
    "find_callers",
    "List the functions/methods that call the function `name` on `line` of `path` (language-server call "
      .. "hierarchy), with the call-site lines. If unavailable, use find_references or search_text.",
    LOCATION,
    { "path", "line", "name" }
  ),
  fn(
    "find_references",
    "List references to the symbol `name` on `line` of `path` (language server; precise, excludes unrelated "
      .. "symbols with the same name). Max 60 results with the line text.",
    LOCATION,
    { "path", "line", "name" }
  ),
}

-- ---------------------------------------------------------------------------
-- LSP helpers (all awaitable)

--- Load a file into a hidden buffer so language servers attach to it.
function M.load(path, method)
  local buf = vim.fn.bufadd(path)
  if not api.nvim_buf_is_loaded(buf) then
    vim.fn.bufload(buf)
    vim.bo[buf].buflisted = false
    -- Make sure filetype detection (and with it LSP attach) ran.
    if vim.bo[buf].filetype == "" then
      api.nvim_buf_call(buf, function()
        vim.cmd("filetype detect")
      end)
    end
  end
  if method then
    for _ = 1, 40 do
      if #vim.lsp.get_clients({ bufnr = buf, method = method }) > 0 then
        break
      end
      util.sleep(100)
    end
  end
  return buf
end

--- Send `method` to every client on `buf` that supports it; returns the list of results.
function M.request(buf, method, params)
  local results = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, method = method })) do
    local p = type(params) == "function" and params(client) or params
    local err, result = await(function(cb)
      local ok = client:request(method, p, function(e, r)
        cb(e, r)
      end, buf)
      if not ok then
        cb("request failed")
      end
    end)
    if not err and result then
      table.insert(results, result)
    end
  end
  return results
end

local function position(buf, row, col, client)
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local character = col
  if client and client.offset_encoding ~= "utf-8" then
    character = vim.str_utfindex(line, client.offset_encoding, math.min(col, #line), false)
  end
  return { line = row, character = character }
end

--- Position params for identifier `name` on 1-based `line` of `path`, or an error string.
local function locate(input, root, method)
  local path = util.resolve(input.path, root)
  if not path then
    return nil, "File not found: " .. tostring(input.path)
  end
  local buf = M.load(path, method)
  local row = math.max(0, math.floor(tonumber(input.line) or 1) - 1)
  local text = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local name = tostring(input.name or "")
  local s = name ~= "" and text:find("%f[%w_]" .. vim.pesc(name) .. "%f[^%w_]") or nil
  if not s then
    return nil, ('"%s" does not appear on line %d of %s: %s'):format(name, row + 1, util.rel(path, root), util.trim(text))
  end
  return buf, function(client)
    return {
      textDocument = { uri = vim.uri_from_bufnr(buf) },
      position = position(buf, row, s - 1, client),
    }
  end
end

local function line_text(uri, row)
  local path = vim.uri_to_fname(uri)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and api.nvim_buf_is_loaded(buf) then
    return util.trim(api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or "")
  end
  local ok, lines = pcall(vim.fn.readfile, path, "", row + 1)
  return ok and util.trim(lines[row + 1] or "") or ""
end

local function kind_name(kind)
  return vim.lsp.protocol.SymbolKind[kind] or "Symbol"
end

function M.incoming_calls(buf, item)
  local calls = {}
  for _, result in ipairs(M.request(buf, "callHierarchy/incomingCalls", { item = item })) do
    vim.list_extend(calls, result)
  end
  return calls
end

-- ---------------------------------------------------------------------------
-- Tools

local function run_tool(name, input, ctx)
  local root = ctx.root

  if name == "search_symbols" then
    local out = {}
    local results = M.request(ctx.buf, "workspace/symbol", { query = tostring(input.query or "") })
    for _, list in ipairs(results) do
      for _, s in ipairs(list) do
        if #out >= 40 then
          break
        end
        local loc = s.location or {}
        local line = loc.range and (loc.range.start.line + 1) or "?"
        table.insert(out, ("%s %s%s — %s:%s"):format(
          kind_name(s.kind),
          s.name,
          s.containerName and s.containerName ~= "" and (" (in " .. s.containerName .. ")") or "",
          loc.uri and util.rel(vim.uri_to_fname(loc.uri), root) or "?",
          line
        ))
      end
    end
    if #out == 0 then
      return #results == 0 and "No language server with workspace symbols is attached; use search_text."
        or "No symbols found."
    end
    return table.concat(out, "\n")
  end

  if name == "search_text" then
    local args = { "rg", "--line-number", "--no-heading", "--color", "never", "--max-count", "5",
      "--max-columns", "200", "--max-columns-preview", input.caseSensitive and "--case-sensitive" or "--smart-case" }
    if input.glob and input.glob ~= "" then
      vim.list_extend(args, { "--glob", input.glob })
    end
    vim.list_extend(args, { "-e", tostring(input.pattern or ""), "." })
    local r = await(function(cb)
      vim.system(args, { cwd = root, text = true, timeout = 20000 }, cb)
    end)
    local lines = {}
    for l in (r.stdout or ""):gmatch("[^\r\n]+") do
      table.insert(lines, (l:gsub("^%.[/\\]", ""):gsub("\\", "/")))
    end
    if #lines == 0 then
      return r.code == 2 and ("Error: " .. util.trim(r.stderr or "")) or "No matches."
    end
    local shown = vim.list_slice(lines, 1, 80)
    return table.concat(shown, "\n")
      .. (#lines > 80 and ("\n… %d more matches, refine the search."):format(#lines - 80) or "")
  end

  if name == "list_files" then
    local r = await(function(cb)
      vim.system({ "rg", "--files", "--glob", tostring(input.glob or "*") }, { cwd = root, text = true, timeout = 20000 }, cb)
    end)
    local files = {}
    for l in (r.stdout or ""):gmatch("[^\r\n]+") do
      if #files >= 100 then
        break
      end
      table.insert(files, (l:gsub("\\", "/")))
    end
    return #files > 0 and table.concat(files, "\n") or "No files matched."
  end

  if name == "read_file" then
    local path = util.resolve(input.path, root)
    if not path then
      return "File not found: " .. tostring(input.path)
    end
    local buf = vim.fn.bufnr(path)
    local lines = (buf ~= -1 and api.nvim_buf_is_loaded(buf)) and api.nvim_buf_get_lines(buf, 0, -1, false)
      or vim.fn.readfile(path)
    local first = math.max(1, math.floor(tonumber(input.startLine) or 1))
    local last = math.min(#lines, math.floor(tonumber(input.endLine) or (first + 199)), first + 199)
    local out = { ("%s (%d lines total)"):format(util.rel(path, root), #lines) }
    for i = first, last do
      table.insert(out, i .. ": " .. lines[i])
    end
    return table.concat(out, "\n")
  end

  if name == "find_callers" then
    local buf, params = locate(input, root, "textDocument/prepareCallHierarchy")
    if not buf then
      return params
    end
    local out = {}
    for _, items in ipairs(M.request(buf, "textDocument/prepareCallHierarchy", params)) do
      for _, item in ipairs(items) do
        for _, call in ipairs(M.incoming_calls(buf, item)) do
          if #out >= 40 then
            break
          end
          local sites = {}
          for i, r in ipairs(call.fromRanges or {}) do
            if i > 3 then
              break
            end
            table.insert(sites, ("    %d: %s"):format(r.start.line + 1, line_text(call.from.uri, r.start.line)))
          end
          table.insert(out, ("%s %s%s — %s:%d\n%s"):format(
            kind_name(call.from.kind),
            call.from.name,
            call.from.detail and call.from.detail ~= "" and (" (" .. call.from.detail .. ")") or "",
            util.rel(vim.uri_to_fname(call.from.uri), root),
            call.from.selectionRange.start.line + 1,
            table.concat(sites, "\n")
          ))
        end
      end
    end
    if #out == 0 then
      return #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/prepareCallHierarchy" }) == 0
          and "No call hierarchy available for this file. Try find_references or search_text."
        or "No callers found."
    end
    return table.concat(out, "\n")
  end

  if name == "find_references" then
    local buf, params = locate(input, root, "textDocument/references")
    if not buf then
      return params
    end
    local out, total = {}, 0
    local results = M.request(buf, "textDocument/references", function(client)
      local p = params(client)
      p.context = { includeDeclaration = false }
      return p
    end)
    for _, refs in ipairs(results) do
      for _, ref in ipairs(refs) do
        total = total + 1
        if #out < 60 then
          table.insert(out, ("%s:%d: %s"):format(
            util.rel(vim.uri_to_fname(ref.uri), root),
            ref.range.start.line + 1,
            line_text(ref.uri, ref.range.start.line)
          ))
        end
      end
    end
    if total == 0 then
      return #results == 0 and "No language server with references for this file. Try search_text."
        or "No references found."
    end
    return table.concat(out, "\n") .. (total > 60 and ("\n… %d more"):format(total - 60) or "")
  end

  return "Unknown tool " .. name
end

local function describe(name, input)
  if name == "search_symbols" then
    return "Searching symbols: " .. tostring(input.query)
  elseif name == "search_text" then
    return "Searching text: " .. util.truncate(tostring(input.pattern), 40)
  elseif name == "list_files" then
    return "Listing files: " .. tostring(input.glob)
  elseif name == "read_file" then
    return "Reading " .. vim.fn.fnamemodify(tostring(input.path), ":t")
  elseif name == "find_callers" then
    return "Finding callers of " .. tostring(input.name)
  elseif name == "find_references" then
    return "Finding references to " .. tostring(input.name)
  end
  return name
end

--- Run the tool loop until the model calls `final`. Returns its arguments, or nil + error.
---@param ctx {buf:integer, root:string, cancelled:boolean, cancel:fun()?, status:fun(text:string)}
function M.agent(ctx, messages, final)
  local final_name = final["function"].name
  local tools = vim.list_extend(vim.deepcopy(M.TOOLS), { final })
  local nudged = false

  for step = 1, MAX_STEPS do
    if ctx.cancelled then
      return nil, "cancelled"
    end
    local last = step == MAX_STEPS
    local err, msg = await(function(cb)
      ctx.cancel = copilot.complete({
        model = require("explai").config.model,
        temperature = 0.1,
        messages = messages,
        tools = last and { final } or tools,
        tool_choice = last and { type = "function", ["function"] = { name = final_name } } or "auto",
      }, cb)
    end)
    if ctx.cancelled then
      return nil, "cancelled"
    end
    if err then
      return nil, err
    end
    table.insert(messages, msg)

    if not msg.tool_calls then
      if nudged then
        return nil, "the model stopped without an answer"
      end
      nudged = true
      table.insert(messages, { role = "user", content = "Continue using the tools, and finish by calling " .. final_name .. "." })
    else
      local inputs = {}
      for i, call in ipairs(msg.tool_calls) do
        local input = util.decode(call["function"].arguments or "{}")
        inputs[i] = type(input) == "table" and input or {}
        if call["function"].name == final_name then
          return inputs[i]
        end
      end
      for i, call in ipairs(msg.tool_calls) do
        local name = call["function"].name
        ctx.status(describe(name, inputs[i]))
        local ok, out = pcall(run_tool, name, inputs[i], ctx)
        if not ok then
          out = "Error: " .. tostring(out)
        end
        table.insert(messages, { role = "tool", tool_call_id = call.id, content = util.truncate(out, MAX_OUTPUT) })
      end
    end
  end
  return nil, "no answer after " .. MAX_STEPS .. " steps"
end

return M
