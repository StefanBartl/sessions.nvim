---@module 'sessions'
---@brief Entry point for sessions.nvim — setup + public API.
---
--- Minimal usage:
---   require("sessions").setup()
---
--- Full config with all options:
---   require("sessions").setup({
---     root         = vim.fn.stdpath("data") .. "/sessions",
---     default_name = "last",
---     branch_aware = true,
---     project_aware = true,
---     autoload     = false,
---     autosave     = true,
---     metadata     = true,
---     hooks = { on_save = nil, on_load = nil },
---     blacklist = { buftypes = {}, filetypes = {}, paths = {} },
---     keymaps = {
---       save = "<leader>ssa", load = "<leader>slo",
---       save_ts = "<leader>sst", list = "<leader>sli",
---     },
---   })

require("sessions.@types")

---@class SessionsAPI
local M = {}

local _setup_done = false

---Configure and activate sessions.nvim (idempotent).
---@param opts? Sessions.Config
function M.setup(opts)
  if _setup_done then return end
  _setup_done = true

  require("sessions.config").setup(opts)

  require("sessions.bindings.usercmds").enable()
  require("sessions.bindings.autocmds").enable()

  local cfg = require("sessions.config").cfg
  if cfg.keymaps ~= false then
    require("sessions.bindings.keymaps").attach(cfg.keymaps or {})

    if cfg.which_key and cfg.which_key.enable then
      pcall(require("sessions.bindings.which_key").setup, cfg.keymaps or {})
    end
  end

  vim.g.loaded_sessions_nvim = 1
end

-- =========================================================
-- Public API (thin wrappers around core — useful for other plugins/keymaps)
-- =========================================================

---Save a session.
---@param name? string  Explicit name; nil = auto-resolve (project/branch-aware)
---@return boolean ok
---@return string|nil path_or_err
function M.save(name)
  return require("sessions.core").save(name)
end

---Load a session.
---@param name? string
---@return boolean, string|nil, string[]|nil
function M.load(name)
  return require("sessions.core").load(name)
end

---List all saved session file paths.
---@return string[]
function M.list()
  return require("sessions.core").list()
end

---Delete a session by name.
---@param name string
---@return boolean, string|nil
function M.delete(name)
  return require("sessions.core").delete(name)
end

---Rename a session.
---@param old_name string
---@param new_name string
---@return boolean, string|nil
function M.rename(old_name, new_name)
  return require("sessions.core").rename(old_name, new_name)
end

---Return the name of the currently active session (nil if none loaded).
---Suitable for use in a statusline component.
---@return string|nil
function M.current()
  return require("sessions.core").current()
end

---Return the metadata for a saved session.
---@param name string
---@return Sessions.Meta|nil
function M.metadata(name)
  return require("sessions.core").metadata(name)
end

return M
