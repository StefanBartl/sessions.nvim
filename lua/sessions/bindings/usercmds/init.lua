---@module 'sessions.bindings.usercmds'
--- Registers :Session <subcommand>, one verb built via lib.nvim's composer
--- (:Verb sub … + <Tab> completion + Markdown docgen), plus a standalone
--- :LastSession convenience command (see below).

local composer = require("lib.nvim.usercmd.composer")

local M = {}

-- Resolve a notifier once per session; graceful fallback if lib.nvim absent.
local _n
local function n()
  if _n then return _n end
  local ok, lib = pcall(require, "lib.nvim.notify")
  if ok then
    _n = lib.create("[sessions]")
  else
    _n = {
      info  = function(msg) vim.notify("[sessions] " .. msg, vim.log.levels.INFO) end,
      warn  = function(msg) vim.notify("[sessions] " .. msg, vim.log.levels.WARN) end,
      error = function(msg) vim.notify("[sessions] " .. msg, vim.log.levels.ERROR) end,
    }
  end
  return _n
end

---@param paths string[]
---@return string[]
local function basenames(paths)
  local out = {}
  for i = 1, #paths do
    out[i] = vim.fn.fnamemodify(paths[i], ":t:r")
  end
  return out
end

---@param list_fn fun(): string[]
---@return fun(lead: string): string[]
local function completer(list_fn)
  return function(lead)
    local out = {}
    for _, name in ipairs(basenames(list_fn())) do
      if lead == "" or name:sub(1, #lead) == lead then
        out[#out + 1] = name
      end
    end
    return out
  end
end

-- Names are dynamic (change on every save/delete), unlike the built-in
-- STRING type's `values` (a static snapshot) — a custom type looks them up
-- fresh on every completion request.
composer.register_type("SESSION", {
  validate = function(raw) return true, raw, nil end,
  complete = completer(function() return require("sessions.core").list() end),
})

composer.register_type("TAB_SESSION", {
  validate = function(raw) return true, raw, nil end,
  complete = completer(function() return require("sessions.core").list_tabs() end),
})

composer.register_type("LAYOUT", {
  validate = function(raw) return true, raw, nil end,
  complete = completer(function() return require("sessions.layout").list() end),
})

local function do_save(name)
  local ok, res = require("sessions.core").save(name)
  if ok then n().info("saved: " .. (res or "?"))
  else       n().error("save failed: " .. (res or "?")) end
end

local function do_load(name)
  local ok, res, hidden = require("sessions.core").load(name)
  if ok then
    n().info("loaded: " .. (res or "?"))
    if hidden and #hidden > 0 then
      n().info("hidden (unsaved): " .. table.concat(hidden, ", "))
    end
  else
    n().error("load failed: " .. (res or "?"))
  end
end

---@return nil
function M.enable()
  composer.verb("Session", {
    desc = "Session save/load/manage",
    routes = {
      { path = { "save" },
        args = { { name = "name", type = "SESSION", optional = true } },
        desc = "Save session [name] (tab-complete to overwrite an existing one)",
        run  = function(ctx) do_save(ctx.args.name) end },

      { path = { "save-timestamp" },
        desc = "Save session with timestamp suffix",
        run  = function() do_save(os.date("sess-%Y%m%d-%H%M%S")) end },

      { path = { "load" },
        args = { { name = "name", type = "SESSION", optional = true } },
        desc = "Load session [name] (omit for the configured default_name)",
        run  = function(ctx) do_load(ctx.args.name) end },

      { path = { "delete" },
        args = { { name = "name", type = "SESSION" } },
        desc = "Delete a session by name",
        run  = function(ctx)
          local ok, res = require("sessions.core").delete(ctx.args.name)
          if ok then n().info("deleted: " .. ctx.args.name)
          else       n().error("delete failed: " .. (res or "?")) end
        end },

      { path = { "rename" },
        args = { { name = "old", type = "SESSION" }, { name = "new", type = "STRING" } },
        desc = "Rename a session: :Session rename <old> <new>",
        run  = function(ctx)
          local ok, res = require("sessions.core").rename(ctx.args.old, ctx.args.new)
          if ok then n().info(("renamed '%s' → '%s'"):format(ctx.args.old, ctx.args.new))
          else       n().error("rename failed: " .. (res or "?")) end
        end },

      { path = { "list" },
        desc = "List all saved sessions",
        run  = function()
          local list = require("sessions.core").list()
          if #list == 0 then n().info("No sessions saved."); return end
          local current = require("sessions.core").current()
          local lines = {}
          for _, p in ipairs(list) do
            local name = vim.fn.fnamemodify(p, ":t:r")
            local meta = require("sessions.core").metadata(name)
            local star   = (name == current) and " *" or "  "
            local ts     = (meta and meta.saved_at) and ("  " .. meta.saved_at) or ""
            local branch = (meta and meta.branch)   and ("  [" .. meta.branch .. "]") or ""
            lines[#lines + 1] = star .. name .. ts .. branch
          end
          n().info(table.concat(lines, "\n"))
        end },

      { path = { "current" },
        desc = "Print the active session name",
        run  = function()
          local cur = require("sessions.core").current()
          n().info(cur and ("Current session: " .. cur) or "No session active.")
        end },

      -- Toggle git skip-worktree on a session file so it can live in a config
      -- repo but be excluded from commits on machines where the paths don't exist.
      { path = { "toggle-track" },
        args = { { name = "name", type = "SESSION", optional = true } },
        desc = "Toggle git skip-worktree on a session file",
        run  = function(ctx) M.toggle_track(ctx.args.name) end },

      -- Tab-scoped sessions: only the current tab's windows, stored
      -- separately from full sessions (root/.tabs/).
      { path = { "save-tab" },
        args = { { name = "name", type = "TAB_SESSION", optional = true } },
        desc = "Save only the current tab's window layout [name]",
        run  = function(ctx)
          local ok, res = require("sessions.core").save_tab(ctx.args.name)
          if ok then n().info("tab session saved: " .. (res or "?"))
          else       n().error("tab session save failed: " .. (res or "?")) end
        end },

      { path = { "load-tab" },
        args = { { name = "name", type = "TAB_SESSION" } },
        desc = "Load a tab session into a new tab: :Session load-tab <name>",
        run  = function(ctx)
          local ok, res = require("sessions.core").load_tab(ctx.args.name)
          if ok then n().info("tab session loaded: " .. (res or "?"))
          else       n().error("tab session load failed: " .. (res or "?")) end
        end },

      -- Window-layout snapshots: split structure only, applied to whatever
      -- buffers are currently open (not tied to specific files).
      { path = { "save-layout" },
        args = { { name = "name", type = "LAYOUT" } },
        desc = "Save the current window-split layout: :Session save-layout <name>",
        run  = function(ctx)
          local ok, res = require("sessions.layout").save(ctx.args.name)
          if ok then n().info("layout saved: " .. (res or "?"))
          else       n().error("layout save failed: " .. (res or "?")) end
        end },

      { path = { "load-layout" },
        args = { { name = "name", type = "LAYOUT" } },
        desc = "Restore a window-split layout: :Session load-layout <name>",
        run  = function(ctx)
          local ok, res = require("sessions.layout").restore(ctx.args.name)
          if ok then n().info("layout restored: " .. (res or "?"))
          else       n().error("layout restore failed: " .. (res or "?")) end
        end },
    },
  })

  -- :LastSession — a plain zero-arg command (not a :Session subcommand) so it
  -- works as `nvim +LastSession` on the CLI. Pure convenience layer over
  -- `:Session load last`; loads the session literally named "last" (the
  -- default autosave_name/default_name — see docs/configuration.md) rather
  -- than relying on the bare-load fallback, so it stays correct even if a
  -- user reconfigures default_name to something else.
  require("lib.nvim.usercmd").create("LastSession", function()
    do_load("last")
  end, { desc = "Load the 'last' session (nvim +LastSession)" })
end

--- Extracted so composer can call it and so the logic is unit-testable
--- without going through a real :command invocation.
---@param name string|nil
function M.toggle_track(name)
  local cfg  = require("sessions.config").cfg
  name = name or require("sessions.core").current() or cfg.default_name
  local file = cfg.root .. "/" .. name .. ".vim"

  if vim.fn.filereadable(file) == 0 then
    n().error("session file not found: " .. file)
    return
  end

  -- Find the git root that contains the session storage directory.
  local git_root
  if vim.system then
    local r = vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = cfg.root, text = true }):wait()
    if r.code == 0 then git_root = vim.trim(r.stdout or "") end
  end
  if not git_root or git_root == "" then
    local ok_argv, run_argv = pcall(require, "lib.nvim.cross.run_argv")
    if ok_argv then
      local ok_run, out = run_argv.run_blocking_captured({ "git", "-C", cfg.root, "rev-parse", "--show-toplevel" })
      git_root = ok_run and vim.trim(out) or ""
    else
      git_root = vim.trim(vim.fn.system(
        "git -C " .. vim.fn.shellescape(cfg.root) .. " rev-parse --show-toplevel 2>/dev/null"
      ))
    end
  end
  if git_root == "" then
    n().error("session root is not inside a git repo (required for :Session toggle-track)")
    return
  end

  local function is_skipped(f)
    if vim.system then
      local r = vim.system({ "git", "ls-files", "-v", "--", f }, { cwd = git_root, text = true }):wait()
      return ((r.stdout or ""):match("^S")) ~= nil
    end
    local ok_argv, run_argv = pcall(require, "lib.nvim.cross.run_argv")
    if ok_argv then
      local _, out = run_argv.run_blocking_captured({ "git", "-C", git_root, "ls-files", "-v", "--", f })
      return (out or ""):match("^S") ~= nil
    end
    local out = vim.fn.system(
      "git -C " .. vim.fn.shellescape(git_root) .. " ls-files -v -- " .. vim.fn.shellescape(f)
    )
    return (out or ""):match("^S") ~= nil
  end

  local skipped = is_skipped(file)
  local toggle_args = skipped
    and { "git", "update-index", "--no-skip-worktree", "--", file }
    or  { "git", "update-index", "--skip-worktree",    "--", file }

  local code
  if vim.system then
    code = vim.system(toggle_args, { cwd = git_root, text = true }):wait().code
  else
    local ok_argv, run_argv = pcall(require, "lib.nvim.cross.run_argv")
    if ok_argv then
      local cwd_args = { "git", "-C", git_root }
      for _, a in ipairs(toggle_args) do cwd_args[#cwd_args + 1] = a end
      local ok_run = run_argv.run_blocking(cwd_args)
      code = ok_run and 0 or 1
    else
      vim.fn.system(table.concat(vim.tbl_map(vim.fn.shellescape, toggle_args), " "))
      code = vim.v.shell_error
    end
  end

  if code ~= 0 then
    n().error("git command failed")
  elseif skipped then
    n().info(name .. ".vim is now tracked in git")
  else
    n().info(name .. ".vim marked as skip-worktree (excluded from git)")
  end
end

return M
