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

---@internal
---@param p string
---@return boolean
local function is_dir(p)
  local st = uv.fs_stat(p)
  return (st ~= nil and st.type == "directory")
end

---@internal
---mkdir() raises (`E739: Cannot create directory`) when the parent cannot be
---created -- a component that already exists as a file, a read-only volume --
---and that used to reach `M.save`/`M.save_tab`'s callers unguarded, contract
---(`boolean, string|nil`) notwithstanding. Reachable from the `VimLeavePre`
---autosave, so a broken session root used to crash Neovim on quit.
---@param dir string
---@return boolean ok
---@return string|nil err
local function ensure_dir(dir)
  if is_dir(dir) then
    return true, nil
  end
  local ok, err = pcall(fn.mkdir, dir, "p")
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

---@internal
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

---@internal
---Apply `cfg.sessionoptions` to `vim.opt.sessionoptions` before a save/load.
local function apply_sessionoptions()
  vim.opt.sessionoptions = require("sessions.config").cfg.sessionoptions
end

---@internal
---@param opt_str string
---@return string
local function strip_tabpages(opt_str)
  local parts = {}
  for part in opt_str:gmatch("[^,]+") do
    if part ~= "tabpages" then
      parts[#parts + 1] = part
    end
  end
  return table.concat(parts, ",")
end

---@internal
---@param cfg Sessions.Config
---@return boolean
local function git_aware(cfg)
  return cfg.branch_aware or cfg.project_aware
end

---@internal
---@param name string|nil
---@param use_auto_resolve boolean|nil
---@return Sessions.Info
---@see sessions.git, sessions.state
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
    -- Load with no explicit name (bare `:Session load`, autoload). Two
    -- candidates, in priority order:
    --   1. The auto-resolved name for the project/branch we are in RIGHT
    --      NOW -- the same resolution a bare `:Session save` would use --
    --      but only when that session actually exists; a project that has
    --      never been saved has no file to prefer.
    --   2. The remembered last-loaded/saved session: `.state.json` in
    --      `cfg.root`, one pointer shared by every project. Right for a
    --      single-workspace setup (branch/project_aware off) or a custom
    --      name that auto-resolve can't reconstruct.
    -- (1) must come first: `.state.json` is global, not per-project, so
    -- preferring it unconditionally meant opening a *different* project
    -- with autoload on could silently load the previous project's session
    -- -- the file still exists, filereadable() says yes, and nothing here
    -- knew it belonged to somewhere else. See docs/configuration.md.
    local auto = git_aware(cfg) and require("sessions.git").resolve_name(cfg) or nil
    if
      auto
      and auto ~= cfg.default_name
      and fn.filereadable(cfg.root .. "/" .. auto .. ".vim") == 1
    then
      n = auto
    else
      local remembered = require("sessions.state").read(cfg).last_loaded
      if remembered and fn.filereadable(cfg.root .. "/" .. remembered .. ".vim") == 1 then
        n = remembered
      else
        n = cfg.default_name
      end
    end
  end
  return { name = n, path = cfg.root .. "/" .. n .. ".vim" }
end

---@internal
---Move every window currently showing `bufnr` onto another listed buffer
---with a real file, so force-deleting a visible blacklisted buffer (e.g. a
---sidebar) does not leave the window on whatever throwaway scratch buffer
---Neovim auto-creates for it -- and does not have :mksession record that
---substitution as if it were the user's actual layout.
---@param bufnr integer
local function switch_windows_off(bufnr)
  local alt = nil
  local altfile = fn.bufnr("#")
  if
    altfile ~= -1
    and altfile ~= bufnr
    and api.nvim_buf_is_valid(altfile)
    and bo[altfile].buflisted
    and api.nvim_buf_get_name(altfile) ~= ""
  then
    alt = altfile
  end
  if not alt then
    for _, b in ipairs(api.nvim_list_bufs()) do
      if
        b ~= bufnr
        and api.nvim_buf_is_valid(b)
        and bo[b].buflisted
        and bo[b].buftype == ""
        and api.nvim_buf_get_name(b) ~= ""
      then
        alt = b
        break
      end
    end
  end
  -- No usable alternate (e.g. every other buffer is itself blacklisted or
  -- unnamed): fall through and let nvim_buf_delete substitute its own
  -- scratch buffer rather than blocking the save over it.
  if not alt then
    return
  end
  -- Only split windows are retargeted. A floating window on a scratch
  -- buffer (a notification toast, a keystroke HUD, a plugin's popup) is that
  -- buffer's window: nvim_buf_delete closes it along with the buffer, and
  -- moving it onto a file first would leave the float open, showing that
  -- file, as if it were part of the layout.
  for _, win in ipairs(api.nvim_list_wins()) do
    if
      api.nvim_win_is_valid(win)
      and api.nvim_win_get_buf(win) == bufnr
      and api.nvim_win_get_config(win).relative == ""
    then
      pcall(api.nvim_win_set_buf, win, alt)
    end
  end
end

---@internal
---True when a non-floating window is showing `bufnr`.
---@param bufnr integer
---@return boolean
local function shown_in_split(bufnr)
  for _, win in ipairs(api.nvim_list_wins()) do
    if
      api.nvim_win_is_valid(win)
      and api.nvim_win_get_buf(win) == bufnr
      and api.nvim_win_get_config(win).relative == ""
    then
      return true
    end
  end
  return false
end

---@internal
---Force-delete any buffer matching `cfg.blacklist` (buftype, filetype, or
---path prefix) before a save, so it never ends up in the session file.
---Unloaded buffers count too: `:mksession` writes every *listed* buffer as
---`badd`, loaded or not, and a session load leaves its own `badd` entries
---unloaded until visited -- gating on "loaded" let a path added to the
---blacklist later be carried from one save to the next forever. (A
---filetype is only set on load, so that check naturally applies to loaded
---buffers alone.)
local function wipe_blacklisted()
  local bl = require("sessions.config").cfg.blacklist
  local bufs = api.nvim_list_bufs()
  for i = 1, #bufs do
    local b = bufs[i]
    if api.nvim_buf_is_valid(b) then
      local bt = bo[b].buftype
      local ft = bo[b].filetype
      local name = api.nvim_buf_get_name(b)
      local bad = (bt ~= "" and vim.tbl_contains(bl.buftypes, bt))
        or (ft ~= "" and vim.tbl_contains(bl.filetypes, ft))
        or (name ~= "" and starts_with_any(name, bl.paths))
      -- Only what :mksession would otherwise record: a listed buffer, or one
      -- a split window is showing. An unlisted scratch buffer that lives in
      -- a floating window or in no window at all (a toast, a keystroke HUD,
      -- a plugin's popup) never reaches the session file, and wiping it
      -- would tear that UI down for nothing.
      if bad and (bo[b].buflisted or shown_in_split(b)) then
        switch_windows_off(b)
        pcall(api.nvim_buf_delete, b, { force = true })
      end
    end
  end
end

---@internal
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

---@internal
---@return Sessions.Meta
---@see sessions.meta
local function build_meta(branch)
  local buffers = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) then
      local nm = api.nvim_buf_get_name(b)
      if nm ~= "" then
        buffers[#buffers + 1] = nm
      end
    end
  end
  return {
    saved_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    cwd = fn.getcwd(),
    branch = branch,
    buffers = buffers,
  }
end

-- =========================================================
-- Public API
-- =========================================================

---@param name string|nil  Explicit name; nil = auto-resolve
---@return boolean ok
---@return string|nil path_or_err
---@see sessions.layout, sessions.portable, sessions.meta
function M.save(name)
  local cfg = require("sessions.config").cfg
  apply_sessionoptions()
  local dir_ok, dir_err = ensure_dir(cfg.root)
  if not dir_ok then
    return false, dir_err
  end
  wipe_blacklisted()

  local si = resolve(name, true) -- save: auto-resolve a project/branch name when unnamed
  local save_cwd = fn.getcwd()
  local ok, err = pcall(vim.cmd.mksession, { args = { si.path }, bang = true })
  if not ok then
    return false, err
  end

  if cfg.relative_paths then
    local rel_ok, rel_err = require("sessions.portable").make_relative(si.path, save_cwd)
    if not rel_ok then
      return false, "relative_paths post-processing failed: " .. tostring(rel_err)
    end
  end

  _current = si.name
  _dirty = false
  -- A save is as much "the session to resume next" as an explicit load --
  -- withholding this left the very first save in a project (before it was
  -- ever explicitly loaded once) unable to be found again by a bare
  -- `:Session load`/autoload, which fell through to whatever `.state.json`
  -- last remembered from a *different* project instead. See M.load() below.
  require("sessions.state").set_last_loaded(cfg, si.name)

  if cfg.metadata then
    local branch = git_aware(cfg) and require("sessions.git").current_branch() or nil
    require("sessions.meta").write(si.path, build_meta(branch))
  end

  if cfg.restore_buffer_order then
    require("sessions.buforder").save(si.path)
  end

  if cfg.hooks.on_save then
    pcall(cfg.hooks.on_save, si.name, si.path)
  end

  return true, si.path
end

--- Tab-scoped save: only the current tab's window layout, stored separately
--- under root/.tabs/ so it can't collide with (or show up alongside) full
--- sessions. Does not touch _current/_dirty/metadata — those track the
--- full workspace session, not tab snapshots.
---@param name string|nil  Explicit name; nil = auto-resolve
---@return boolean ok
---@return string|nil path_or_err
function M.save_tab(name)
  local cfg = require("sessions.config").cfg
  local dir_ok, dir_err = ensure_dir(cfg.root .. "/.tabs")
  if not dir_ok then
    return false, dir_err
  end
  wipe_blacklisted()

  local si = resolve(name, true)
  local path = cfg.root .. "/.tabs/" .. si.name .. ".vim"
  local save_cwd = fn.getcwd()

  -- Drop "tabpages" for this one save so :mksession only records the
  -- current tab's windows, regardless of the user's configured sessionoptions.
  vim.opt.sessionoptions = strip_tabpages(cfg.sessionoptions)
  local ok, err = pcall(vim.cmd.mksession, { args = { path }, bang = true })
  apply_sessionoptions()
  if not ok then
    return false, err
  end

  if cfg.relative_paths then
    local rel_ok, rel_err = require("sessions.portable").make_relative(path, save_cwd)
    if not rel_ok then
      return false, "relative_paths post-processing failed: " .. tostring(rel_err)
    end
  end

  if cfg.hooks.on_save then
    pcall(cfg.hooks.on_save, si.name, path)
  end

  return true, path
end

---@param name string|nil
---@return boolean ok
---@return string|nil path_or_err
---@return string[]|nil hidden_modified_bufs
---@see sessions.portable, sessions.state
function M.load(name)
  local cfg = require("sessions.config").cfg
  local si = resolve(name, false) -- load: fall back to the remembered last-loaded, then default_name

  if fn.filereadable(si.path) == 0 then
    return false, "no such session: " .. si.path
  end

  apply_sessionoptions()

  -- Collapse windows before sourcing to avoid E445 from the session's `only`/`tabonly`.
  local hidden = modified_buffer_names()
  pcall(function()
    vim.cmd("silent! only!")
  end)
  pcall(function()
    vim.cmd("silent! tabonly!")
  end)

  local source_path, is_temp = si.path, false
  if cfg.relative_paths or next(cfg.root_remap) then
    source_path, is_temp =
      require("sessions.portable").prepare_for_load(si.path, fn.getcwd(), cfg.root_remap)
  end

  local ok, err = pcall(vim.cmd.source, source_path)
  if is_temp then
    os.remove(source_path)
  end
  if not ok then
    return false, err
  end

  _current = si.name
  _dirty = false
  require("sessions.state").set_last_loaded(cfg, si.name)

  if cfg.restore_buffer_order then
    require("sessions.buforder").restore(si.path)
  end

  if cfg.hooks.on_load then
    pcall(cfg.hooks.on_load, si.name, si.path)
  end

  return true, si.path, hidden
end

--- Tab-scoped load: opens a new tab and restores a tab-scoped snapshot
--- into it, leaving every other tab untouched (unlike M.load, which
--- collapses to a single tab). Name is required — unlike full sessions,
--- tab snapshots have no "remembered last" or default_name fallback.
---@param name string  Tab-session name (as passed to M.save_tab)
---@return boolean ok
---@return string|nil path_or_err
function M.load_tab(name)
  if type(name) ~= "string" or name == "" then
    return false, "tab session name required"
  end

  local cfg = require("sessions.config").cfg
  local path = cfg.root .. "/.tabs/" .. name .. ".vim"

  if fn.filereadable(path) == 0 then
    return false, "no such tab session: " .. path
  end

  apply_sessionoptions()
  vim.cmd("tabnew")

  local source_path, is_temp = path, false
  if cfg.relative_paths or next(cfg.root_remap) then
    source_path, is_temp =
      require("sessions.portable").prepare_for_load(path, fn.getcwd(), cfg.root_remap)
  end

  local ok, err = pcall(vim.cmd.source, source_path)
  if is_temp then
    os.remove(source_path)
  end
  if not ok then
    pcall(function()
      vim.cmd("tabclose")
    end)
    return false, err
  end

  if cfg.hooks.on_load then
    pcall(cfg.hooks.on_load, name, path)
  end

  return true, path
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
  if not is_dir(cfg.root) then
    return {}
  end
  -- globpath reads its first argument as a pattern, not a path: an 8.3 short
  -- component in cfg.root (e.g. Windows' %TEMP% for a long profile name)
  -- contains a literal "~", which glob then tries to resolve as a
  -- home-directory reference and silently returns an empty list for.
  local files = fn.globpath(require("lib.nvim.fs.globbable")(cfg.root), "*.vim", false, true)
  table.sort(files)
  return files
end

---@return string[]  Absolute paths to .vim tab-session files under root/.tabs/
function M.list_tabs()
  local cfg = require("sessions.config").cfg
  local dir = cfg.root .. "/.tabs"
  if not is_dir(dir) then
    return {}
  end
  local files = fn.globpath(require("lib.nvim.fs.globbable")(dir), "*.vim", false, true)
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
  require("sessions.buforder").delete(path)
  if _current == name then
    _current = nil
  end
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
  require("sessions.buforder").rename(old_path, new_path)
  if _current == old_name then
    _current = new_name
  end
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
