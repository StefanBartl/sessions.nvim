---@module 'sessions.meta'
--- Companion JSON metadata alongside each session file.
--- Stored as .{name}.json in the same directory so it is hidden on Unix
--- and not confused with session files by :Session list.

require("sessions.@types")

---@class SessionsMeta
local M = {}

---@internal
---@param session_path string
---@return string
local function meta_path(session_path)
  local dir = vim.fn.fnamemodify(session_path, ":h")
  local base = vim.fn.fnamemodify(session_path, ":t:r")
  return dir .. "/." .. base .. ".json"
end

---@internal
---Not `vim.NIL`/`lib.lua.null`'s NULL marker (JSON `null` decodes to one of
---those, not Lua `nil`) and actually a string.
---@param v any
---@return boolean
local function is_str(v)
  return type(v) == "string"
end

---@internal
---Cap on trusted `buffers` entries -- a sidecar is untrusted input (hand-
---editable, or synced in from another machine/plugin version via `:Session
---toggle-track`) and has no other natural bound on that list's length.
local MAX_BUFFERS = 2000

---@internal
---Validate a decoded sidecar against `Sessions.Meta`'s shape before it is
---trusted: every field is type-checked, and the first bad one rejects the
---whole read, the same contract `sessions.layout` already applies to its own
---persisted snapshot (`is_valid_node`). Without this, a field that decoded
---to a table (JSON `null`, or any non-string value) sailed past the
---`meta.field and ...` guards at the call sites -- both are truthy -- and
---then crashed on string concatenation or `ipairs()`.
---@param data any
---@return boolean
local function is_valid(data)
  if type(data) ~= "table" then
    return false
  end
  if data.saved_at ~= nil and not is_str(data.saved_at) then
    return false
  end
  if data.branch ~= nil and not is_str(data.branch) then
    return false
  end
  if data.cwd ~= nil and not is_str(data.cwd) then
    return false
  end
  if data.buffers ~= nil then
    if type(data.buffers) ~= "table" or #data.buffers > MAX_BUFFERS then
      return false
    end
    for _, b in ipairs(data.buffers) do
      if not is_str(b) then
        return false
      end
    end
  end
  return true
end

---@param session_path string
---@param data Sessions.Meta
---@return boolean
---@see sessions.core
function M.write(session_path, data)
  local ok = require("lib.nvim.fs.json").write(meta_path(session_path), data)
  return ok
end

---@param session_path string
---@return Sessions.Meta|nil  nil for a missing sidecar, or one that fails validation
function M.read(session_path)
  local data = require("lib.nvim.fs.json").read(meta_path(session_path))
  if not is_valid(data) then
    return nil
  end
  return data
end

---@param session_path string
function M.delete(session_path)
  os.remove(meta_path(session_path))
end

---@param old_path string
---@param new_path string
function M.rename(old_path, new_path)
  local old_mp = meta_path(old_path)
  local new_mp = meta_path(new_path)
  local content = require("lib.nvim.fs.read")(old_mp)
  if not content then
    return
  end
  local ok = require("lib.nvim.fs.write.to_file")(new_mp, content)
  if ok then
    os.remove(old_mp)
  end
end

return M
