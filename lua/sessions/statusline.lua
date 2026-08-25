---@module 'sessions.statusline'
---@brief Ready-made statusline component for lualine/heirline consumers.
---@description
--- `component()` is a hotpath: statusline plugins invoke it on every redraw
--- (potentially many times per second while typing/moving the cursor), so
--- the merged-options table is memoized per distinct `opts` table (weak keys
--- — see LUA_NVIM.md "Metatables, schwache Tabellen, Memoisierung") instead
--- of being rebuilt on every call.

require("sessions.@types")

---@class SessionsStatusline
local M = {}

---@type Sessions.StatuslineOpts
local DEFAULTS = {
  icon = "",
  dirty_icon = " *",
  empty = "",
}

-- Weak-keyed cache: merged-opts table per distinct `opts` table passed by the
-- caller (lualine/heirline pass the same table reference on every redraw).
-- Entries are dropped automatically once the caller's opts table is GC'd.
---@type table<Sessions.StatuslineOpts, Sessions.StatuslineOpts>
local _merged_cache = setmetatable({}, { __mode = "k" })

---@internal
---@param opts? Sessions.StatuslineOpts
---@return Sessions.StatuslineOpts
local function resolve_opts(opts)
  if not opts then
    return DEFAULTS
  end
  local cached = _merged_cache[opts]
  if cached then
    return cached
  end
  local merged = vim.tbl_extend("force", DEFAULTS, opts)
  _merged_cache[opts] = merged
  return merged
end

---Build a statusline string: `<icon><name><dirty_icon?>`, or `opts.empty`
---when no session is active. Safe to call unconditionally on every redraw.
---@param opts? Sessions.StatuslineOpts
---@return string
function M.component(opts)
  local resolved = resolve_opts(opts)
  local core = require("sessions.core")
  local name = core.current()
  if not name then
    return resolved.empty
  end
  local dirty = core.dirty() and resolved.dirty_icon or ""
  return resolved.icon .. name .. dirty
end

return M
