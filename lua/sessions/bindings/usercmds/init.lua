---@module 'sessions.bindings.usercmds'
--- Registers :Session <subcommand>, one verb built via lib.nvim's composer
--- (:Verb sub … + <Tab> completion + Markdown docgen), plus a standalone
--- :LastSession convenience command (see below).

local composer = require("lib.nvim.bindings.usercmd.composer")

---@class SessionsBindingsUsercmds
local M = {}

-- Resolve a notifier once per session; graceful fallback if lib.nvim absent.
local _n
---@internal
---@return table
local function n()
  if _n then
    return _n
  end
  local ok, lib = pcall(require, "lib.nvim.notify")
  if ok then
    _n = lib.create("[sessions]")
  else
    _n = {
      info = function(msg)
        vim.notify("[sessions] " .. msg, vim.log.levels.INFO)
      end,
      warn = function(msg)
        vim.notify("[sessions] " .. msg, vim.log.levels.WARN)
      end,
      error = function(msg)
        vim.notify("[sessions] " .. msg, vim.log.levels.ERROR)
      end,
    }
  end
  return _n
end

---@internal
---@param paths string[]
---@return string[]
local function basenames(paths)
  local out = {}
  for i = 1, #paths do
    out[i] = vim.fn.fnamemodify(paths[i], ":t:r")
  end
  return out
end

---@internal
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
  validate = function(raw)
    return true, raw, nil
  end,
  complete = completer(function()
    return require("sessions.core").list()
  end),
})

composer.register_type("TAB_SESSION", {
  validate = function(raw)
    return true, raw, nil
  end,
  complete = completer(function()
    return require("sessions.core").list_tabs()
  end),
})

composer.register_type("LAYOUT", {
  validate = function(raw)
    return true, raw, nil
  end,
  complete = completer(function()
    return require("sessions.layout").list()
  end),
})

---@internal
---@param name string|nil
---@see sessions.core
local function do_save(name)
  local ok, res = require("sessions.core").save(name)
  if ok then
    n().info("saved: " .. (res or "?"))
  else
    n().error("save failed: " .. (res or "?"))
  end
end

---@internal
---@param name string|nil
---@see sessions.core
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

---Register the `:Session <subcommand>` verb, `:LastSession`, and
---`:SessionLoad` user commands.
---@return nil
---@see sessions.picker
function M.enable()
  composer.verb("Session", {
    desc = "Session save/load/manage",
    routes = {
      {
        path = { "save" },
        args = { { name = "name", type = "SESSION", optional = true } },
        desc = "Save session [name] (tab-complete to overwrite an existing one)",
        run = function(ctx)
          do_save(ctx.args.name)
        end,
      },

      {
        path = { "save-timestamp" },
        desc = "Save session with timestamp suffix",
        run = function()
          do_save(os.date("sess-%Y%m%d-%H%M%S") --[[@as string]])
        end,
      },

      {
        path = { "load" },
        args = { { name = "name", type = "SESSION", optional = true } },
        desc = "Load session [name] (omit for the configured default_name)",
        run = function(ctx)
          do_load(ctx.args.name)
        end,
      },

      {
        path = { "delete" },
        args = { { name = "name", type = "SESSION" } },
        desc = "Delete a session by name",
        run = function(ctx)
          local ok, res = require("sessions.core").delete(ctx.args.name)
          if ok then
            n().info("deleted: " .. ctx.args.name)
          else
            n().error("delete failed: " .. (res or "?"))
          end
        end,
      },

      {
        path = { "rename" },
        args = { { name = "old", type = "SESSION" }, { name = "new", type = "STRING" } },
        desc = "Rename a session: :Session rename <old> <new>",
        run = function(ctx)
          local ok, res = require("sessions.core").rename(ctx.args.old, ctx.args.new)
          if ok then
            n().info(("renamed '%s' → '%s'"):format(ctx.args.old, ctx.args.new))
          else
            n().error("rename failed: " .. (res or "?"))
          end
        end,
      },

      {
        path = { "list" },
        desc = "List all saved sessions",
        run = function()
          local list = require("sessions.core").list()
          if #list == 0 then
            n().info("No sessions saved.")
            return
          end
          local current = require("sessions.core").current()
          local lines = {}
          for _, p in ipairs(list) do
            local name = vim.fn.fnamemodify(p, ":t:r")
            local meta = require("sessions.core").metadata(name)
            local star = (name == current) and " *" or "  "
            local ts = (meta and meta.saved_at) and ("  " .. meta.saved_at) or ""
            local branch = (meta and meta.branch) and ("  [" .. meta.branch .. "]") or ""
            lines[#lines + 1] = star .. name .. ts .. branch
          end
          n().info(table.concat(lines, "\n"))
        end,
      },

      {
        path = { "current" },
        desc = "Print the active session name",
        run = function()
          local cur = require("sessions.core").current()
          n().info(cur and ("Current session: " .. cur) or "No session active.")
        end,
      },

      -- Toggle git skip-worktree on a session file so it can live in a config
      -- repo but be excluded from commits on machines where the paths don't exist.
      {
        path = { "toggle-track" },
        args = { { name = "name", type = "SESSION", optional = true } },
        desc = "Toggle git skip-worktree on a session file",
        run = function(ctx)
          M.toggle_track(ctx.args.name)
        end,
      },

      -- Tab-scoped sessions: only the current tab's windows, stored
      -- separately from full sessions (root/.tabs/).
      {
        path = { "save-tab" },
        args = { { name = "name", type = "TAB_SESSION", optional = true } },
        desc = "Save only the current tab's window layout [name]",
        run = function(ctx)
          local ok, res = require("sessions.core").save_tab(ctx.args.name)
          if ok then
            n().info("tab session saved: " .. (res or "?"))
          else
            n().error("tab session save failed: " .. (res or "?"))
          end
        end,
      },

      {
        path = { "load-tab" },
        args = { { name = "name", type = "TAB_SESSION" } },
        desc = "Load a tab session into a new tab: :Session load-tab <name>",
        run = function(ctx)
          local ok, res = require("sessions.core").load_tab(ctx.args.name)
          if ok then
            n().info("tab session loaded: " .. (res or "?"))
          else
            n().error("tab session load failed: " .. (res or "?"))
          end
        end,
      },

      -- Window-layout snapshots: split structure only, applied to whatever
      -- buffers are currently open (not tied to specific files).
      {
        path = { "save-layout" },
        args = { { name = "name", type = "LAYOUT" } },
        desc = "Save the current window-split layout: :Session save-layout <name>",
        run = function(ctx)
          local ok, res = require("sessions.layout").save(ctx.args.name)
          if ok then
            n().info("layout saved: " .. (res or "?"))
          else
            n().error("layout save failed: " .. (res or "?"))
          end
        end,
      },

      {
        path = { "load-layout" },
        args = { { name = "name", type = "LAYOUT" } },
        desc = "Restore a window-split layout: :Session load-layout <name>",
        run = function(ctx)
          local ok, res = require("sessions.layout").restore(ctx.args.name)
          if ok then
            n().info("layout restored: " .. (res or "?"))
          else
            n().error("layout restore failed: " .. (res or "?"))
          end
        end,
      },
    },
  })

  -- :LastSession — a plain zero-arg command (not a :Session subcommand) so it
  -- works as `nvim +LastSession` on the CLI. Pure convenience layer over
  -- `:Session load last`; loads the session literally named "last" (the
  -- default autosave_name/default_name — see docs/configuration.md) rather
  -- than relying on the bare-load fallback, so it stays correct even if a
  -- user reconfigures default_name to something else.
  require("lib.nvim.bindings.usercmd").create("LastSession", function()
    do_load("last")
  end, { desc = "Load the 'last' session (nvim +LastSession)" })

  -- :SessionLoad — session picker with live preview (Snacks.picker or
  -- telescope.nvim, whichever is installed). A plain zero-arg command, not
  -- a :Session subcommand, matching :LastSession's convention.
  require("lib.nvim.bindings.usercmd").create("SessionLoad", function()
    require("sessions.picker").pick()
  end, { desc = "Open the session picker with preview (Snacks/Telescope)" })
end

--- Extracted so composer can call it and so the logic is unit-testable
--- without going through a real :command invocation.
---@param name string|nil
function M.toggle_track(name)
  local cfg = require("sessions.config").cfg
  name = name or require("sessions.core").current() or cfg.default_name
  local file = cfg.root .. "/" .. name .. ".vim"

  if not require("lib.nvim.fs.is_readable_file")(file) then
    n().error("session file not found: " .. file)
    return
  end

  -- Find the git root that contains the session storage directory.
  --
  -- Previously this spawned `git rev-parse --show-toplevel` (blocking). A
  -- plain upward filesystem search answers the same question with stat()
  -- calls only. `.git` is matched as directory *and* file so worktrees and
  -- submodules resolve correctly.
  local found = vim.fs.find(".git", { path = cfg.root, upward = true, limit = 1 })
  local git_root = found and found[1] and vim.fs.dirname(found[1]) or ""
  if git_root == "" then
    n().error("session root is not inside a git repo (required for :Session toggle-track)")
    return
  end

  -- The two remaining steps genuinely need git. They used to run through
  -- `vim.system():wait()` / `vim.fn.system()`, which froze the UI for the
  -- duration of two process spawns. They are now chained via vim.system()
  -- callbacks; toggle_track() returns immediately and reports through notify.
  if not vim.system then
    -- Neovim < 0.10: no async process API available here. Fall back to the
    -- blocking path rather than silently doing nothing.
    local ok_argv, run_argv = pcall(require, "lib.nvim.cross.run_argv")
    if not ok_argv then
      n().error("vim.system() unavailable and lib.nvim.cross.run_argv missing")
      return
    end
    local _, out =
      run_argv.run_blocking_captured({ "git", "-C", git_root, "ls-files", "-v", "--", file })
    local skipped = ((out or ""):match("^S")) ~= nil
    local args = {
      "git",
      "-C",
      git_root,
      "update-index",
      skipped and "--no-skip-worktree" or "--skip-worktree",
      "--",
      file,
    }
    local ok_run = run_argv.run_blocking(args)
    if not ok_run then
      n().error("git command failed")
    elseif skipped then
      n().info(name .. ".vim is now tracked in git")
    else
      n().info(name .. ".vim marked as skip-worktree (excluded from git)")
    end
    return
  end

  vim.system({ "git", "ls-files", "-v", "--", file }, { cwd = git_root, text = true }, function(ls)
    local skipped = ((ls.stdout or ""):match("^S")) ~= nil
    local toggle_args = skipped and { "git", "update-index", "--no-skip-worktree", "--", file }
      or { "git", "update-index", "--skip-worktree", "--", file }

    vim.system(toggle_args, { cwd = git_root, text = true }, function(res)
      -- vim.system callbacks run off the main loop: notify must be scheduled.
      vim.schedule(function()
        if res.code ~= 0 then
          n().error("git command failed")
        elseif skipped then
          n().info(name .. ".vim is now tracked in git")
        else
          n().info(name .. ".vim marked as skip-worktree (excluded from git)")
        end
      end)
    end)
  end)
end

return M
