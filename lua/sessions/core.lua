---@module 'sessions.core'
---@brief Save, load, list, delete, rename logic. No UI side-effects.

require("sessions.@types")

local fn, bo, api = vim.fn, vim.bo, vim.api
local uv = vim.uv or vim.loop

---@class SessionsCore
local M = {}

---@type string|nil
local _current = nil

---@type boolean
local _dirty = false

---@return string|nil
function M.current()
  return _current
end

---True when the active session's window/buffer layout has changed since the
---last save/load (i.e. an autosave, if enabled, would capture something new).
---@return boolean
function M.dirty()
  return _dirty
end

---Mark the active session dirty. Called by structural autocmds
---(BufAdd/BufDelete/WinNew/...) registered in bindings.autocmds.
function M.mark_dirty()
  if _current then
    _dirty = true
  end
end

-- =========================================================
-- Internal helpers
-- =========================================================

---@param p string
---@return boolean
local function is_dir(p)
  local st = uv.fs_stat(p)
  return (st ~= nil and st.type == "directory")
end

---@param dir string
local function ensure_dir(dir)
  if not is_dir(dir) then
    fn.mkdir(dir, "p")
  end
end

---@param s string
---@param list string[]
---@return boolean
local function starts_with_any(s, list)
  for i = 1, #list do
    local pref = list[i]
    if pref ~= nil and s:sub(1, #pref) == pref then
      return true
    end
  end
  return false
end

local function apply_sessionoptions()
  vim.opt.sessionoptions = require("sessions.config").cfg.sessionoptions
end

---@param cfg Sessions.Config
---@return boolean
local function git_aware(cfg)
  return cfg.branch_aware or cfg.project_aware
end

---@param name string|nil
---@param use_auto_resolve boolean|nil
---@return Sessions.Info
local function resolve(name, use_auto_resolve)
  local cfg = require("sessions.config").cfg
  local n
  if type(name) == "string" and name ~= "" then
    n = name
  elseif use_auto_resolve then
    -- Save: auto-resolve project/branch name when configured. sessions.git
    -- is only required here, so it never loads (and never shells out)
    -- unless branch_aware or project_aware actually asks for it.
    n = git_aware(cfg) and require("sessions.git").resolve_name(cfg) or cfg.default_name
  else
    -- Load: prefer the remembered last-loaded session (if it still exists
    -- on disk), falling back to default_name otherwise.
    local remembered = require("sessions.state").read(cfg).last_loaded
    if remembered and fn.filereadable(cfg.root .. "/" .. remembered .. ".vim") == 1 then
      n = remembered
    else
      n = cfg.default_name
    end
  end
  return { name = n, path = cfg.root .. "/" .. n .. ".vim" }
end

local function wipe_blacklisted()
  local bl = require("sessions.config").cfg.blacklist
  local bufs = api.nvim_list_bufs()
  for i = 1, #bufs do
    local b = bufs[i]
    if api.nvim_buf_is_loaded(b) then
      local bt   = bo[b].buftype
      local ft   = bo[b].filetype
      local name = api.nvim_buf_get_name(b)
      local bad  = (bt ~= "" and vim.tbl_contains(bl.buftypes, bt))
        or (ft ~= "" and vim.tbl_contains(bl.filetypes, ft))
        or (name ~= "" and starts_with_any(name, bl.paths))
      if bad then
        pcall(api.nvim_buf_delete, b, { force = true })
      end
    end
  end
end

---@return string[]
local function modified_buffer_names()
  local out = {}
  local bufs = api.nvim_list_bufs()
  for i = 1, #bufs do
    local b = bufs[i]
    if api.nvim_buf_is_loaded(b) and vim.bo[b].modified then
      local nm = api.nvim_buf_get_name(b)
      out[#out + 1] = (nm ~= "" and nm) or ("[No Name #" .. b .. "]")
    end
  end
  return out
end

---@return Sessions.Meta
local function build_meta(branch)
  local buffers = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) then
      local nm = api.nvim_buf_get_name(b)
      if nm ~= "" then buffers[#buffers + 1] = nm end
    end
  end
  return {
    saved_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    cwd      = fn.getcwd(),
    branch   = branch,
    buffers  = buffers,
  }
end

-- =========================================================
-- Public API
-- =========================================================

---@param name string|nil  Explicit name; nil = auto-resolve
---@return boolean ok
---@return string|nil path_or_err
function M.save(name)
  local cfg = require("sessions.config").cfg
  apply_sessionoptions()
  ensure_dir(cfg.root)
  wipe_blacklisted()

  local si = resolve(name, true)  -- use_auto_resolve = true for save
  local ok, err = pcall(vim.cmd.mksession, { args = { si.path }, bang = true })
  if not ok then
    return false, err
  end

  _current = si.name
  _dirty = false

  if cfg.metadata then
    local branch = git_aware(cfg) and require("sessions.git").current_branch() or nil
    require("sessions.meta").write(si.path, build_meta(branch))
  end

  if cfg.hooks.on_save then
    pcall(cfg.hooks.on_save, si.name, si.path)
  end

  return true, si.path
end

---@param name string|nil
---@return boolean ok
---@return string|nil path_or_err
---@return string[]|nil hidden_modified_bufs
function M.load(name)
  local cfg = require("sessions.config").cfg
  local si = resolve(name, false)  -- use_auto_resolve = false, use default_name ("last")

  if fn.filereadable(si.path) == 0 then
    return false, "no such session: " .. si.path
  end

  apply_sessionoptions()

  -- Collapse windows before sourcing to avoid E445 from the session's `only`/`tabonly`.
  local hidden = modified_buffer_names()
  pcall(vim.cmd, "silent! only!")
  pcall(vim.cmd, "silent! tabonly!")

  local ok, err = pcall(vim.cmd.source, si.path)
  if not ok then
    return false, err
  end

  _current = si.name
  _dirty = false
  require("sessions.state").set_last_loaded(cfg, si.name)

  if cfg.hooks.on_load then
    pcall(cfg.hooks.on_load, si.name, si.path)
  end

  return true, si.path, hidden
end

---Resolve what `M.load(nil)` would load, without loading it. Used by the
---`autoload = "ask"` prompt to show the target session name up front.
---@return Sessions.Info info
---@return boolean exists
function M.peek()
  local si = resolve(nil, false)
  return si, fn.filereadable(si.path) == 1
end

---@return string[]  Absolute paths to .vim session files
function M.list()
  local cfg = require("sessions.config").cfg
  if not is_dir(cfg.root) then return {} end
  local files = fn.globpath(cfg.root, "*.vim", false, true)
  table.sort(files)
  return files
end

---@param name string
---@return boolean ok
---@return string|nil path_or_err
function M.delete(name)
  local cfg = require("sessions.config").cfg
  local path = cfg.root .. "/" .. name .. ".vim"
  if fn.filereadable(path) == 0 then
    return false, "session not found: " .. name
  end
  local ok = os.remove(path)
  if not ok then
    return false, "failed to delete: " .. path
  end
  require("sessions.meta").delete(path)
  if _current == name then _current = nil end
  return true, path
end

---@param old_name string
---@param new_name string
---@return boolean ok
---@return string|nil path_or_err
function M.rename(old_name, new_name)
  local cfg = require("sessions.config").cfg
  local old_path = cfg.root .. "/" .. old_name .. ".vim"
  local new_path = cfg.root .. "/" .. new_name .. ".vim"

  if fn.filereadable(old_path) == 0 then
    return false, "session not found: " .. old_name
  end
  if fn.filereadable(new_path) == 1 then
    return false, "session already exists: " .. new_name
  end

  local ok = os.rename(old_path, new_path)
  if not ok then
    return false, "rename failed"
  end
  require("sessions.meta").rename(old_path, new_path)
  if _current == old_name then _current = new_name end
  return true, new_path
end

---@param name string
---@return Sessions.Meta|nil
function M.metadata(name)
  local cfg = require("sessions.config").cfg
  local path = cfg.root .. "/" .. name .. ".vim"
  return require("sessions.meta").read(path)
end

return M
