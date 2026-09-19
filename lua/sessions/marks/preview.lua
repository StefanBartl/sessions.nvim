---@module 'sessions.marks.preview'
--- A read-only look at mark `n` without leaving the buffer you are in: a
--- centred float over one reusable scratch buffer, cursor at the entry's
--- remembered position, `q` or `<Esc>` to close. Large files are capped and
--- say so at the point where the cut is.

---@class SessionsMarksPreview
local M = {}

local uv = vim.uv or vim.loop

---@type { buf: integer|nil, win: integer|nil }
local STATE = { buf = nil, win = nil }

---@internal
---@return table
local function notify()
  local ok, lib = pcall(require, "lib.nvim.notify")
  if ok then
    return lib.create("[sessions.marks]")
  end
  return {
    info = function(msg)
      vim.notify("[sessions.marks] " .. msg, vim.log.levels.INFO)
    end,
    warn = function(msg)
      vim.notify("[sessions.marks] " .. msg, vim.log.levels.WARN)
    end,
  }
end

---@internal
---@return { max_kb: integer, max_lines: integer }
local function limits()
  local cfg = require("sessions.config").get().marks
  local p = cfg and cfg.preview or {}
  return {
    max_kb = type(p.max_kb) == "number" and p.max_kb or 1536,
    max_lines = type(p.max_lines) == "number" and p.max_lines or 4000,
  }
end

---@internal
---Read a file's lines; the head only past `max_kb`, so a huge log does not
---turn into one huge string.
---@param path string
---@return string[]|nil lines
---@return boolean truncated
local function read_lines(path)
  local st = uv.fs_stat(path)
  if not st or st.type ~= "file" then
    return nil, false
  end
  local lim = limits()
  if st.size > lim.max_kb * 1024 then
    local ok, lines = pcall(vim.fn.readfile, path, "", lim.max_lines)
    if not ok then
      return nil, false
    end
    return lines, #lines >= lim.max_lines
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, false
  end
  return lines, false
end

---@internal
---@return integer buf, integer win
local function ensure_window()
  if
    STATE.win
    and vim.api.nvim_win_is_valid(STATE.win)
    and STATE.buf
    and vim.api.nvim_buf_is_valid(STATE.buf)
  then
    return STATE.buf, STATE.win
  end
  if not (STATE.buf and vim.api.nvim_buf_is_valid(STATE.buf)) then
    STATE.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[STATE.buf].buftype = "nofile"
    vim.bo[STATE.buf].swapfile = false
    vim.bo[STATE.buf].bufhidden = "wipe"
  end
  local w = math.max(40, math.floor(vim.o.columns * 0.7))
  local h = math.max(8, math.floor(vim.o.lines * 0.7))
  STATE.win = vim.api.nvim_open_win(STATE.buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    width = w,
    height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
  })
  vim.wo[STATE.win].wrap = true
  vim.wo[STATE.win].cursorline = true
  vim.wo[STATE.win].number = true
  vim.b[STATE.buf].sessions_marks_preview = true
  local ok, nice_quit = pcall(require, "lib.nvim.window.nice_quit")
  if ok then
    nice_quit(STATE.win, { force = true })
  else
    for _, lhs in ipairs({ "q", "<Esc>" }) do
      vim.keymap.set("n", lhs, function()
        pcall(vim.api.nvim_win_close, STATE.win, true)
      end, { buffer = STATE.buf, nowait = true })
    end
  end
  return STATE.buf, STATE.win
end

---Preview a file at a position.
---@param path string
---@param row integer|nil  1-based
---@param col integer|nil  0-based
---@return boolean ok
function M.open_path(path, row, col)
  local lines, truncated = read_lines(path)
  if not lines then
    notify().warn("cannot read " .. tostring(path))
    return false
  end
  if truncated then
    local lim = limits()
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("--- preview truncated at %d lines (file is larger than %d KB) ---"):format(
      lim.max_lines,
      lim.max_kb
    )
  end
  local buf, win = ensure_window()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local ft = vim.filetype.match({ filename = path }) or ""
  if ft ~= "" then
    vim.bo[buf].filetype = ft
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.api.nvim_buf_set_name(buf, "sessions://preview/" .. vim.fn.fnamemodify(path, ":t"))
  local total = math.max(#lines, 1)
  row = math.min(math.max(tonumber(row) or 1, 1), total)
  col = math.max(tonumber(col) or 0, 0)
  if vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_cursor, win, { row, col })
  end
  return true
end

---Preview mark `n`.
---@param n integer
---@return boolean ok
---@return string|nil err
function M.open_index(n)
  local items = require("sessions.marks").list()
  local it = items[n]
  if not it then
    return false, ("no mark at %d (%d listed)"):format(n, #items)
  end
  return M.open_path(it.path, it.row, it.col), nil
end

---Is the preview window open?
---@return boolean
function M.is_open()
  return STATE.win ~= nil and vim.api.nvim_win_is_valid(STATE.win)
end

return M
