---@module 'sessions.meta'
--- Companion JSON metadata alongside each session file.
--- Stored as .{name}.json in the same directory so it is hidden on Unix
--- and not confused with session files by :SessionList.

require("sessions.@types")

local M = {}

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
function M.write(session_path, data)
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then return false end
  local mp = meta_path(session_path)
  local f = io.open(mp, "w")
  if not f then return false end
  f:write(encoded)
  f:close()
  return true
end

---@param session_path string
---@return Sessions.Meta|nil
function M.read(session_path)
  local mp = meta_path(session_path)
  local f = io.open(mp, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok then return nil end
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
  local f = io.open(old_mp, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  local wf = io.open(new_mp, "w")
  if wf then
    wf:write(content)
    wf:close()
    os.remove(old_mp)
  end
end

return M
