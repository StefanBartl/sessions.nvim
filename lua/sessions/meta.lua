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

---@param session_path string
---@param data Sessions.Meta
---@return boolean
---@see sessions.core
function M.write(session_path, data)
  local ok = require("lib.nvim.fs.json").write(meta_path(session_path), data)
  return ok
end

---@param session_path string
---@return Sessions.Meta|nil
function M.read(session_path)
  local data = require("lib.nvim.fs.json").read(meta_path(session_path))
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
