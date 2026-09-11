---@module 'sessions.portable'
--- Cross-device/cross-OS session portability. Neovim's own `:mksession`
--- already writes buffer paths relative to `cwd` when possible (with
--- "curdir" in 'sessionoptions'), but the embedded `cd`/`lcd` line and any
--- paths outside `cwd` stay host-absolute. This module post-processes the
--- plain-text .vim file to close that gap, rather than touching
--- Neovim's own session-writing internals.

local fn = vim.fn

---@class SessionsPortable
local M = {}

local PLACEHOLDER = "{{SESSION_ROOT}}"

---@internal
---@param path string
---@return string
local function read_all(path)
  return require("lib.nvim.fs.read")(path) or ""
end

---@internal
---@param path string
---@param content string
local function write_all(path, content)
  require("lib.nvim.fs.write.to_file")(path, content)
end

---@internal
---Escape a literal string for use as a Lua pattern (the "needle").
---@param s string
---@return string
local function pat_escape(s)
  return (s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"))
end

---@internal
---Escape a literal string for use as a gsub replacement (the "value").
---@param s string
---@return string
local function repl_escape(s)
  return (s:gsub("%%", "%%%%"))
end

---@internal
---Replace every occurrence of `needle` in `content` with `replacement`, but
---only where `needle` ends at a real path boundary -- the next byte is not
---a filename-continuation character (word char, `.`, `-`, `~`), or there is
---no next byte at all.
---
---A plain `gsub` on the literal cwd matches it as a bare string prefix, so a
---sibling directory that merely starts with the same text (`E:/repos/ui.nvim`
---is a prefix of `E:/repos/ui.nvim-backup`, common in a repos folder full of
---similarly-named plugin checkouts) had ITS paths corrupted too -- rewritten
---to `{{SESSION_ROOT}}-backup/...`. Harmless on a same-machine save+load
---(the two substitutions cancel out), but wrong the moment `root_remap` or a
---different machine re-anchors the placeholder to a directory the sibling
---was never actually under.
---@param content string
---@param needle string
---@param replacement string
---@return string
local function boundary_replace(content, needle, replacement)
  if needle == "" then
    return content
  end
  local out = {}
  local pos = 1
  while true do
    local s, e = content:find(needle, pos, true) -- plain find, no pattern chars
    if not s then
      out[#out + 1] = content:sub(pos)
      break
    end
    local after = content:sub(e + 1, e + 1)
    if after == "" or not after:match("[%w_%-%.~]") then
      out[#out + 1] = content:sub(pos, s - 1)
      out[#out + 1] = replacement
      pos = e + 1
    else
      -- Not a boundary (e.g. "ui.nvim" inside "ui.nvim-backup"): keep the
      -- literal text and resume right after this hit, so an overlapping
      -- later match starting mid-needle is still found.
      out[#out + 1] = content:sub(pos, s)
      pos = s + 1
    end
  end
  return table.concat(out)
end

---@internal
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
---@see sessions.core
function M.make_relative(session_path, cwd)
  local content = read_all(session_path)
  if content == "" then
    return
  end

  for _, needle in ipairs(spellings(cwd)) do
    content = boundary_replace(content, needle, PLACEHOLDER)
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
  if content == "" then
    return session_path, false
  end

  local changed = false

  if content:find(PLACEHOLDER, 1, true) then
    content = content:gsub(pat_escape(PLACEHOLDER), (repl_escape(cwd:gsub("\\", "/"))))
    changed = true
  end

  for old_root, new_root in pairs(root_remap or {}) do
    if type(old_root) == "string" and type(new_root) == "string" and content:find(old_root, 1, true) then
      local rewritten = boundary_replace(content, old_root, new_root)
      if rewritten ~= content then
        content = rewritten
        changed = true
      end
    end
  end

  if not changed then
    return session_path, false
  end

  local tmp = fn.tempname() .. ".vim"
  write_all(tmp, content)
  return tmp, true
end

return M
