-- GitHub Copilot chat API client. Reuses the sign-in from copilot.lua / copilot.vim
-- (github-copilot/apps.json), exchanges it for a short-lived Copilot token and calls
-- the OpenAI-compatible /chat/completions endpoint with curl.
--
-- Secrets never go on the curl command line: headers are passed through a curl config
-- on stdin (`-K -`) and the request body through a temp file.
local util = require("explai.util")

local M = {}

local token_cache ---@type {token:string, expires_at:integer, api:string}?
local VERSION = "0.1.0"

local function config_dir()
  if vim.fn.has("win32") == 1 then
    return (vim.env.LOCALAPPDATA or (vim.env.USERPROFILE .. "/AppData/Local")) .. "/github-copilot"
  end
  return (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config")) .. "/github-copilot"
end

local function oauth_tokens()
  local tokens = {}
  for _, name in ipairs({ "apps.json", "hosts.json" }) do
    local path = config_dir() .. "/" .. name
    if vim.fn.filereadable(path) == 1 then
      local data = util.decode(table.concat(vim.fn.readfile(path), "\n"))
      for key, v in pairs(data or {}) do
        if type(key) == "string" and key:find("github.com", 1, true) and type(v) == "table" and v.oauth_token then
          table.insert(tokens, v.oauth_token)
        end
      end
    end
  end
  return tokens
end

local function header_config(headers)
  local lines = {}
  for _, h in ipairs(headers) do
    table.insert(lines, ('header = "%s"'):format(h:gsub('"', '\\"')))
  end
  return table.concat(lines, "\n") .. "\n"
end

local function chat_headers(tok)
  return header_config({
    "Authorization: Bearer " .. tok.token,
    "Content-Type: application/json",
    "Copilot-Integration-Id: vscode-chat",
    "Editor-Version: Neovim/" .. tostring(vim.version()),
    "Editor-Plugin-Version: explai.nvim/" .. VERSION,
    "User-Agent: explai.nvim/" .. VERSION,
    "Openai-Intent: conversation-panel",
  })
end

local function api_error(body)
  local data = util.decode(body)
  if type(data) == "table" then
    local e = data.error
    if type(e) == "table" and e.message then
      return e.message
    end
    if type(e) == "string" then
      return e
    end
    if data.message then
      return data.message
    end
  end
  body = util.trim(body or "")
  return body ~= "" and util.truncate(body, 300) or "empty response"
end

--- Get a valid Copilot API token. cb(err, {token, api}).
function M.token(cb)
  if token_cache and token_cache.expires_at - 120 > os.time() then
    return cb(nil, token_cache)
  end
  local list = oauth_tokens()
  if #list == 0 then
    return cb("No GitHub Copilot sign-in found. Sign in with :Copilot auth first.")
  end
  local i = 0
  local function try()
    i = i + 1
    if i > #list then
      return cb("Could not get a Copilot token. Is your Copilot subscription active? Try :Copilot auth.")
    end
    vim.system(
      { "curl", "-sS", "-K", "-", "https://api.github.com/copilot_internal/v2/token" },
      {
        text = true,
        stdin = header_config({
          "Authorization: token " .. list[i],
          "Accept: application/json",
          "User-Agent: explai.nvim/" .. VERSION,
        }),
      },
      vim.schedule_wrap(function(r)
        local data = r.code == 0 and util.decode(r.stdout or "") or nil
        if type(data) == "table" and data.token then
          token_cache = {
            token = data.token,
            expires_at = data.expires_at or (os.time() + 600),
            api = (data.endpoints and data.endpoints.api) or "https://api.githubcopilot.com",
          }
          cb(nil, token_cache)
        else
          try()
        end
      end)
    )
  end
  try()
end

local function post(tok, path, body, stream, on_stdout, on_exit)
  local file = vim.fn.tempname()
  vim.fn.writefile({ vim.json.encode(body) }, file, "b")
  local cmd = { "curl", "-sS", "-K", "-", "-X", "POST", tok.api .. path, "--data-binary", "@" .. file }
  if stream then
    table.insert(cmd, 2, "-N")
  end
  return vim.system(cmd, { text = true, stdin = chat_headers(tok), stdout = on_stdout }, function(r)
    os.remove(file)
    on_exit(r)
  end)
end

--- Stream a chat completion. on_delta(text) per chunk, on_done(err). Returns a cancel function.
function M.stream(body, on_delta, on_done)
  local job, cancelled = nil, false
  M.token(function(err, tok)
    if cancelled then
      return
    end
    if err then
      return on_done(err)
    end
    body = vim.tbl_extend("force", body, { stream = true })
    local pending, raw, got_data = "", {}, false
    job = post(tok, "/chat/completions", body, true, function(_, data)
      if not data then
        return
      end
      table.insert(raw, data)
      pending = pending .. data
      while true do
        local nl = pending:find("\n", 1, true)
        if not nl then
          break
        end
        local line = pending:sub(1, nl - 1):gsub("\r$", "")
        pending = pending:sub(nl + 1)
        local payload = line:match("^data:%s?(.*)$")
        if payload and payload ~= "[DONE]" then
          got_data = true
          local ev = util.decode(payload)
          for _, choice in ipairs(type(ev) == "table" and ev.choices or {}) do
            local text = choice.delta and choice.delta.content
            if type(text) == "string" and text ~= "" then
              vim.schedule(function()
                if not cancelled then
                  on_delta(text)
                end
              end)
            end
          end
        end
      end
    end, function(r)
      vim.schedule(function()
        if cancelled then
          return
        end
        if r.code ~= 0 then
          on_done("curl failed: " .. util.trim(r.stderr or ""))
        elseif not got_data then
          if (table.concat(raw)):find("unauthorized", 1, true) then
            token_cache = nil
          end
          on_done(api_error(table.concat(raw)))
        else
          on_done(nil)
        end
      end)
    end)
  end)
  return function()
    cancelled = true
    if job then
      pcall(job.kill, job, 15)
    end
  end
end

--- One non-streamed completion (used for tool calls). cb(err, assistant_message).
--- Returns a cancel function.
function M.complete(body, cb)
  local job, cancelled = nil, false
  M.token(function(err, tok)
    if cancelled then
      return
    end
    if err then
      return cb(err)
    end
    body = vim.tbl_extend("force", body, { stream = false })
    job = post(tok, "/chat/completions", body, false, nil, function(r)
      vim.schedule(function()
        if cancelled then
          return
        end
        if r.code ~= 0 then
          return cb("curl failed: " .. util.trim(r.stderr or ""))
        end
        local data = util.decode(r.stdout or "")
        if type(data) ~= "table" or type(data.choices) ~= "table" then
          if (r.stdout or ""):find("unauthorized", 1, true) then
            token_cache = nil
          end
          return cb(api_error(r.stdout))
        end
        -- Copilot can split text and tool calls over several choices: merge them.
        local texts, calls = {}, {}
        for _, choice in ipairs(data.choices) do
          local m = choice.message or {}
          if type(m.content) == "string" and m.content ~= "" then
            table.insert(texts, m.content)
          end
          for _, call in ipairs(m.tool_calls or {}) do
            table.insert(calls, call)
          end
        end
        cb(nil, {
          role = "assistant",
          content = #texts > 0 and table.concat(texts, "\n") or vim.NIL,
          tool_calls = #calls > 0 and calls or nil,
        })
      end)
    end)
  end)
  return function()
    cancelled = true
    if job then
      pcall(job.kill, job, 15)
    end
  end
end

--- List chat models available to this account. cb(err, {{id, name}...})
function M.models(cb)
  M.token(function(err, tok)
    if err then
      return cb(err)
    end
    vim.system(
      { "curl", "-sS", "-K", "-", tok.api .. "/models" },
      { text = true, stdin = chat_headers(tok) },
      vim.schedule_wrap(function(r)
        local data = r.code == 0 and util.decode(r.stdout or "") or nil
        if type(data) ~= "table" or type(data.data) ~= "table" then
          return cb(api_error(r.stdout))
        end
        local list = {}
        for _, m in ipairs(data.data) do
          local caps = m.capabilities or {}
          if caps.type == "chat" and m.model_picker_enabled ~= false then
            table.insert(list, { id = m.id, name = m.name or m.id })
          end
        end
        cb(nil, list)
      end)
    )
  end)
end

return M
