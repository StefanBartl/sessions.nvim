---@module 'sessions.state'
---@brief Tiny persistent state file (distinct from per-session metadata) that
---@description
--- remembers the last explicitly-loaded session name across restarts, so
--- `:Session load` (no name) and autoload can resume exactly where the user
--- left off instead of always falling back to `default_name`.

---@class SessionsState
local M = {}

---@internal
---@param cfg Sessions.Config
---@return string
local function state_path(cfg)
  return cfg.root .. "/.state.json"
end

---@param cfg Sessions.Config
---@return { last_loaded: string|nil }
---@see sessions.core
function M.read(cfg)
  local data = require("lib.nvim.fs.json").read(state_path(cfg))
  if type(data) ~= "table" then return {} end
  return data
end

---@param cfg Sessions.Config
---@param name string
function M.set_last_loaded(cfg, name)
  require("lib.nvim.fs.json").write(state_path(cfg), { last_loaded = name })
end

return M
