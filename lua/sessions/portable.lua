---@module 'sessions.portable'
--- Cross-device/cross-OS session portability. Neovim's own `:mksession`
--- already writes buffer paths relative to `cwd` when possible (with
--- "curdir" in 'sessionoptions'), but the embedded `cd`/`lcd` line and any
--- paths outside `cwd` stay host-absolute. This module post-processes the
--- plain-text .vim file to close that gap, rather than touching
--- Neovim's own session-writing internals.

local fn = vim.fn

local M = {}

local PLACEHOLDER = "{{SESSION_ROOT}}"

---@param path string
---@return string
local function read_all(path)
  local f = io.open(path, "r")
  if not f then return "" end
  local content = f:read("*a")
  f:close()
  return content
end

---@param path string
---@param content string
local function write_all(path, content)
  local f = io.open(path, "w")
  if not f then return end
  f:write(content)
  f:close()
end

---Escape a literal string for use as a Lua pattern (the "needle").
---@param s string
---@return string
local function pat_escape(s)
  return (s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"))
end

---Escape a literal string for use as a gsub replacement (the "value").
---@param s string
---@return string
local function repl_escape(s)
  return (s:gsub("%%", "%%%%"))
end

---Forward-slashed absolute form and the `fnamemodify(..., ':~')` form,
---mirroring the two spellings :mksession itself may write for `dir`.
---@param dir string
---@return string[]
local function spellings(dir)
  local out = {}
  local slashed = dir:gsub("\\", "/")
  out[#out + 1] = slashed
  local tilde = fn.fnamemodify(dir, ":~"):gsub("\\", "/")
  if tilde ~= slashed then
    out[#out + 1] = tilde
  end
  return out
end

---Replace every occurrence of `cwd` (in the spellings :mksession may use)
---in the saved session file with a portable placeholder, so the file no
---longer pins itself to the machine it was saved on.
---@param session_path string
---@param cwd string
function M.make_relative(session_path, cwd)
  local content = read_all(session_path)
  if content == "" then return end

  for _, needle in ipairs(spellings(cwd)) do
    content = content:gsub(pat_escape(needle), (repl_escape(PLACEHOLDER)))
  end

  write_all(session_path, content)
end

---Build a load-ready copy of `session_path` with the placeholder re-anchored
---to `cwd` and any `root_remap` prefixes translated, without mutating the
---stored file (so it stays correct for other machines/OSes that may share
---it, e.g. via `:Session toggle-track`). Returns the original path
---unchanged if no rewriting was needed.
---@param session_path string
---@param cwd string
---@param root_remap table<string, string>|nil
---@return string path_to_source
---@return boolean is_temp_copy
function M.prepare_for_load(session_path, cwd, root_remap)
  local content = read_all(session_path)
  if content == "" then return session_path, false end

  local changed = false

  if content:find(PLACEHOLDER, 1, true) then
    content = content:gsub(pat_escape(PLACEHOLDER), (repl_escape(cwd:gsub("\\", "/"))))
    changed = true
  end

  for old_root, new_root in pairs(root_remap or {}) do
    if type(old_root) == "string" and type(new_root) == "string" and content:find(pat_escape(old_root)) then
      content = content:gsub(pat_escape(old_root), (repl_escape(new_root)))
      changed = true
    end
  end

  if not changed then return session_path, false end

  local tmp = fn.tempname() .. ".vim"
  write_all(tmp, content)
  return tmp, true
end

return M
