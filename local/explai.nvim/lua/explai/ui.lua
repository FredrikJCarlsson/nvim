-- The Explai floating window: anchored to a line of code (it scrolls with it), stays
-- open until closed (q / <Esc>), streams content, and can be brought back later.
--
-- A "view" is a plain table:
--   id        string   same id = update the open window in place (streaming)
--   kind      string?  shown in the title, e.g. "Detailed", "Callers"
--   where     string?  shown in the title, e.g. "ImportService.cs:120–135"
--   anchor    {buf, win, row}  0-based row the window is attached to
--   prefer    "below"|"above"
--   highlight {buf, first, last}?  0-based rows to highlight while open
--   lines     string[] markdown
--   loading   boolean  spinner in the title; closing cancels via on_cancel
--   hints     string?  key hints for the footer
--   meta      string?  model · time for the footer
--   plain     string?  what `y` copies (defaults to the lines)
--   document  string[]? what `o` opens in a split (defaults to the lines)
--   links     table<integer, {path, line}>?  <CR> on that window line jumps there
--   keys      table<string, fun()>?  extra buffer-local keys
local M = {}
local api = vim.api

local ns = api.nvim_create_namespace("explai")
local hl_ns = api.nvim_create_namespace("explai_range")
local augroup = api.nvim_create_augroup("explai_float", { clear = true })
local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local S = { win = nil, buf = nil, view = nil, timer = nil, frame = 1, last = nil }

local function cfg()
  return require("explai").config
end

local function stop_spinner()
  if S.timer then
    S.timer:stop()
    S.timer:close()
    S.timer = nil
  end
end

function M.is_open()
  return S.win ~= nil and api.nvim_win_is_valid(S.win)
end

--- id of the open view, or nil
function M.current_id()
  return M.is_open() and S.view and S.view.id or nil
end

function M.is_loading()
  return M.is_open() and S.view and S.view.loading or false
end

local function title_chunks(view)
  local icon = view.loading and spinner[S.frame] or "✦"
  local t = { { " " .. icon .. " Explai ", "ExplaiTitle" } }
  if view.kind then
    table.insert(t, { "· " .. view.kind .. " ", "ExplaiTitle" })
  end
  if view.where then
    table.insert(t, { "· " .. view.where .. " ", "ExplaiMuted" })
  end
  return t
end

local function footer_chunks(view)
  local f = {}
  if view.hints then
    table.insert(f, { " " .. view.hints .. " ", "ExplaiMuted" })
  end
  if view.meta then
    table.insert(f, { " " .. view.meta .. " ", "ExplaiMeta" })
  end
  return #f > 0 and f or nil
end

local function chunks_width(chunks)
  local w = 0
  for _, c in ipairs(chunks or {}) do
    w = w + vim.fn.strdisplaywidth(c[1])
  end
  return w
end

local function anchor_pos(view)
  local a = view.anchor
  if a.mark then
    local ok, pos = pcall(api.nvim_buf_get_extmark_by_id, a.buf, ns, a.mark, {})
    if ok and pos[1] then
      return pos[1]
    end
  end
  return a.row
end

local function anchor_win(view)
  local a = view.anchor
  if a.win and api.nvim_win_is_valid(a.win) and api.nvim_win_get_buf(a.win) == a.buf then
    return a.win
  end
  local w = vim.fn.bufwinid(a.buf)
  return w ~= -1 and w or nil
end

local function layout(view, win)
  local row = anchor_pos(view)
  local win_width = api.nvim_win_get_width(win)
  local max_w = math.max(30, math.min(cfg().max_width, win_width - 6))

  local w = math.max(chunks_width(title_chunks(view)), chunks_width(footer_chunks(view))) + 2
  for _, l in ipairs(view.lines) do
    w = math.max(w, vim.fn.strdisplaywidth(l) + 1)
  end
  w = math.min(math.max(w, 40), max_w)

  local h = 0
  for _, l in ipairs(view.lines) do
    h = h + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / w))
  end

  -- Room above/below the anchor line inside the window.
  local line = api.nvim_buf_get_lines(view.anchor.buf, row, row + 1, false)[1] or ""
  local indent = math.max(0, (line:find("%S") or 1) - 1)
  local screen = vim.fn.screenpos(win, row + 1, 1).row
  local top = vim.fn.win_screenpos(win)[1]
  local below, above = 1000, 0
  if screen > 0 then
    below = top + api.nvim_win_get_height(win) - 1 - screen
    above = screen - top
  end
  local room = math.max(below, above) - 2
  h = math.max(1, math.min(h, cfg().max_height, math.max(room, 3)))

  local want = h + 2
  local up = (view.prefer == "above" and above >= want) or (view.prefer ~= "above" and below < want and above > below)
  return {
    relative = "win",
    win = win,
    bufpos = { row, math.min(indent, win_width - w - 4) },
    row = up and -want or 1,
    col = 0,
    width = w,
    height = h,
  }
end

local function set_lines(lines)
  vim.bo[S.buf].modifiable = true
  api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  vim.bo[S.buf].modifiable = false
end

local function clear_highlight(view)
  local h = view and view.highlight
  if h and api.nvim_buf_is_valid(h.buf) then
    api.nvim_buf_clear_namespace(h.buf, hl_ns, 0, -1)
  end
end

-- <Esc> in normal mode, in any window, closes the popup. Done with vim.on_key instead of
-- a mapping so LazyVim's own <Esc> mapping keeps working, and because a window can't be
-- closed from inside an <expr> mapping.
local ESC = vim.keycode("<Esc>")
local esc_ns = api.nvim_create_namespace("explai_esc")

local function watch_esc()
  vim.on_key(function(_, typed)
    if typed == ESC and api.nvim_get_mode().mode == "n" and api.nvim_get_current_win() ~= S.win then
      vim.schedule(M.close)
    end
  end, esc_ns)
end

local function remove_esc()
  vim.on_key(nil, esc_ns)
end

function M.close()
  stop_spinner()
  local view = S.view
  S.view = nil
  if S.win and api.nvim_win_is_valid(S.win) then
    api.nvim_win_close(S.win, true)
  end
  S.win, S.buf = nil, nil
  clear_highlight(view)
  remove_esc()
  api.nvim_clear_autocmds({ group = augroup })
  if view and view.loading and view.on_cancel then
    view.on_cancel()
  end
end

function M.focus()
  if M.is_open() then
    api.nvim_set_current_win(S.win)
  end
end

--- Jump to {path, line} in the window the float belongs to.
function M.jump(link, view)
  view = view or S.view
  local win = view and anchor_win(view) or api.nvim_get_current_win()
  M.close()
  if win and api.nvim_win_is_valid(win) then
    api.nvim_set_current_win(win)
  end
  vim.cmd("normal! m'")
  vim.cmd.edit(vim.fn.fnameescape(link.path))
  local last = api.nvim_buf_line_count(0)
  api.nvim_win_set_cursor(0, { math.min(math.max(link.line, 1), last), 0 })
  vim.cmd("normal! ^zz")
end

local function open_document()
  local view = S.view
  if not view then
    return
  end
  local lines = view.document or view.lines
  local win = anchor_win(view)
  M.close()
  if win then
    api.nvim_set_current_win(win)
  end
  vim.cmd("botright vsplit")
  local buf = api.nvim_create_buf(true, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"
  pcall(api.nvim_buf_set_name, buf, "explai://" .. (view.kind or "explain"):lower() .. "/" .. buf)
  api.nvim_win_set_buf(0, buf)
  vim.wo.wrap, vim.wo.linebreak = true, true
end

local function setup_buffer(view)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = "Explai: " .. desc })
  end
  map("q", M.close, "close")
  map("<Esc>", M.close, "close")
  map("y", function()
    local v = S.view
    if v then
      vim.fn.setreg("+", v.plain or table.concat(v.lines, "\n"))
      vim.notify("Explai: copied", vim.log.levels.INFO)
    end
  end, "copy")
  map("o", open_document, "open as document")
  map("<CR>", function()
    local v = S.view
    local link = v and v.links and v.links[api.nvim_win_get_cursor(0)[1]]
    if link then
      M.jump(link, v)
    end
  end, "jump to location")
  for lhs in pairs(view.keys or {}) do
    map(lhs, function()
      local fn = S.view and S.view.keys and S.view.keys[lhs]
      if fn then
        fn()
      end
    end, lhs)
  end
  return buf
end

local function watch(view)
  api.nvim_clear_autocmds({ group = augroup })
  local a = view.anchor
  api.nvim_create_autocmd("InsertEnter", {
    group = augroup,
    buffer = a.buf,
    callback = function()
      M.close()
    end,
  })
  api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    callback = function(ev)
      local v = S.view
      if v and ev.buf ~= a.buf and ev.buf ~= S.buf and not anchor_win(v) then
        M.close()
      end
    end,
  })
  api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    group = augroup,
    buffer = a.buf,
    callback = function()
      vim.schedule(M.close)
    end,
  })
  -- Keep the window sized/placed when the editor is resized.
  api.nvim_create_autocmd("VimResized", {
    group = augroup,
    callback = function()
      if S.view then
        M.show(S.view)
      end
    end,
  })
  watch_esc()
end

--- Show a view (or update the open one in place when the id matches).
function M.show(view)
  local a = view.anchor
  if not api.nvim_buf_is_valid(a.buf) then
    return
  end
  if not a.mark then
    a.mark = api.nvim_buf_set_extmark(a.buf, ns, math.min(a.row, api.nvim_buf_line_count(a.buf) - 1), 0, {})
  end
  local win = anchor_win(view)
  if not win then
    return
  end
  a.win = win

  local reuse = M.is_open() and S.view ~= nil and S.view.id == view.id
  if not reuse then
    M.close()
    S.buf = setup_buffer(view)
  end
  S.view = view
  set_lines(view.lines)

  local conf = layout(view, win)
  conf.border = cfg().border
  conf.title = title_chunks(view)
  conf.title_pos = "left"
  conf.footer = footer_chunks(view) or ""
  conf.footer_pos = "right"
  if reuse then
    api.nvim_win_set_config(S.win, conf)
  else
    conf.style = "minimal"
    conf.focusable = true
    conf.zindex = 45
    conf.noautocmd = true
    S.win = api.nvim_open_win(S.buf, false, conf)
    local wo = vim.wo[S.win]
    wo.wrap, wo.linebreak, wo.breakindent = true, true, true
    wo.conceallevel, wo.concealcursor = 2, "nc"
    wo.winhighlight = "NormalFloat:ExplaiNormal,FloatBorder:ExplaiBorder"
    wo.foldenable, wo.spell = false, false
    watch(view)
    if view.highlight and api.nvim_buf_is_valid(view.highlight.buf) then
      local h = view.highlight
      api.nvim_buf_clear_namespace(h.buf, hl_ns, 0, -1)
      local last = math.min(h.last, api.nvim_buf_line_count(h.buf) - 1)
      for r = h.first, last do
        api.nvim_buf_set_extmark(h.buf, hl_ns, r, 0, { line_hl_group = "ExplaiRange", priority = 5 })
      end
    end
  end

  if view.loading then
    if not S.timer then
      S.timer = vim.uv.new_timer()
      S.timer:start(
        100,
        100,
        vim.schedule_wrap(function()
          if not M.is_open() or not S.view or not S.view.loading then
            return stop_spinner()
          end
          S.frame = S.frame % #spinner + 1
          api.nvim_win_set_config(S.win, { title = title_chunks(S.view), title_pos = "left" })
        end)
      )
    end
  else
    stop_spinner()
    S.last = view
  end
end

--- Update the progress text of the open loading view.
function M.status(id, text)
  if M.current_id() == id and S.view.loading then
    S.view.lines = { "_" .. text .. "…_" }
    M.show(S.view)
  end
end

function M.remember(view)
  S.last = view
end

--- Bring back the last finished popup, opening its buffer if needed.
function M.reopen()
  local v = S.last
  if not v or not api.nvim_buf_is_valid(v.anchor.buf) then
    vim.notify("Explai: nothing to show yet.", vim.log.levels.INFO)
    return
  end
  if M.current_id() == v.id then
    return M.focus()
  end
  local win = vim.fn.bufwinid(v.anchor.buf)
  if win == -1 then
    win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, v.anchor.buf)
  end
  api.nvim_set_current_win(win)
  local row = anchor_pos(v)
  api.nvim_win_set_cursor(win, { row + 1, 0 })
  vim.cmd("normal! ^")
  v.anchor.win = win
  M.show(v)
end

function M.setup_highlights()
  local function link(name, target)
    api.nvim_set_hl(0, name, { link = target, default = true })
  end
  link("ExplaiTitle", "FloatTitle")
  link("ExplaiMuted", "Comment")
  link("ExplaiMeta", "Comment")
  link("ExplaiNormal", "NormalFloat")
  link("ExplaiBorder", "FloatBorder")
  link("ExplaiRange", "Visual")
end

return M
