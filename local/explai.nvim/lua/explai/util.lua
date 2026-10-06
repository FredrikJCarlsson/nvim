-- Small helpers: coroutine-based async, paths and strings.
local M = {}

local function resume(co, ...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    vim.schedule(function()
      vim.notify("Explai: " .. debug.traceback(co, err), vim.log.levels.ERROR)
    end)
  end
end

--- Run `fn` as a coroutine so it can use `await`.
function M.run(fn, ...)
  resume(coroutine.create(fn), ...)
end

--- Inside `run`: call `start(cb)` and wait until it calls `cb(...)`; returns cb's arguments.
function M.await(start)
  local co = assert(coroutine.running(), "Explai: await called outside a coroutine")
  start(function(...)
    local args = vim.F.pack_len(...)
    vim.schedule(function()
      resume(co, vim.F.unpack_len(args))
    end)
  end)
  return coroutine.yield()
end

function M.sleep(ms)
  return M.await(function(cb)
    vim.defer_fn(cb, ms)
  end)
end

--- Project root: LazyVim's root detection when available, else cwd.
function M.root(buf)
  local ok, root = pcall(function()
    return LazyVim.root({ buf = buf })
  end)
  return M.normalize(ok and root or vim.fn.getcwd())
end

function M.normalize(path)
  return (vim.fs.normalize(path):gsub("/$", ""))
end

--- Path relative to `root` (forward slashes), or the normalized path if outside it.
function M.rel(path, root)
  path = M.normalize(path)
  local prefix = root .. "/"
  if path:sub(1, #prefix):lower() == prefix:lower() then
    return path:sub(#prefix + 1)
  end
  return path
end

--- Resolve a path the model gave back (absolute or root-relative) to an existing file.
function M.resolve(path, root)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  path = path:gsub("\\", "/"):gsub("^%./", ""):gsub(":%d+[-%d]*$", "")
  for _, candidate in ipairs({ path, root .. "/" .. path }) do
    if vim.fn.filereadable(candidate) == 1 then
      return M.normalize(vim.fn.fnamemodify(candidate, ":p"))
    end
  end
  return nil
end

function M.truncate(s, n)
  if #s <= n then
    return s
  end
  return s:sub(1, n - 1) .. "…"
end

function M.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

M.json_opts = { luanil = { object = true, array = true } }

function M.decode(s)
  local ok, data = pcall(vim.json.decode, s, M.json_opts)
  if ok then
    return data
  end
  return nil
end

return M
