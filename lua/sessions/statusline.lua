---@module 'sessions.statusline'
--- Ready-made statusline component for lualine/heirline consumers.

require("sessions.@types")

local M = {}

---@type Sessions.StatuslineOpts
local DEFAULTS = {
  icon = "",
  dirty_icon = " *",
  empty = "",
}

---Build a statusline string: `<icon><name><dirty_icon?>`, or `opts.empty`
---when no session is active. Safe to call unconditionally on every redraw.
---@param opts? Sessions.StatuslineOpts
---@return string
function M.component(opts)
  opts = vim.tbl_extend("force", DEFAULTS, opts or {})
  local core = require("sessions.core")
  local name = core.current()
  if not name then
    return opts.empty
  end
  local dirty = core.dirty() and opts.dirty_icon or ""
  return opts.icon .. name .. dirty
end

return M
