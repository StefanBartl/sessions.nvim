---@module 'sessions.state'
--- Tiny persistent state file (distinct from per-session metadata) that
--- remembers the last explicitly-loaded session name across restarts, so
--- `:Session load` (no name) and autoload can resume exactly where the user
--- left off instead of always falling back to `default_name`.

local M = {}

---@param cfg Sessions.Config
---@return string
local function state_path(cfg)
  return cfg.root .. "/.state.json"
end

---@param cfg Sessions.Config
---@return { last_loaded: string|nil }
function M.read(cfg)
  local f = io.open(state_path(cfg), "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then return {} end
  return data
end

---@param cfg Sessions.Config
---@param name string
function M.set_last_loaded(cfg, name)
  local ok, encoded = pcall(vim.json.encode, { last_loaded = name })
  if not ok then return end
  local f = io.open(state_path(cfg), "w")
  if not f then return end
  f:write(encoded)
  f:close()
end

return M
