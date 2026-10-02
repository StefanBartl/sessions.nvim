---@module 'sessions.bindings.usercmds'
--- Registers :Session <subcommand>, one verb built via lib.nvim's composer
--- (:Verb sub … + <Tab> completion + Markdown docgen), plus a standalone
--- :LastSession convenience command (see below).

local composer = require("lib.nvim.bindings.usercmd.composer")

---@class SessionsBindingsUsercmds
local M = {}

-- Resolve a notifier once per session (lazily-memoized: unlike
-- bindings/autocmds' eager module-load-time `n`, this is only built the
-- first time a route actually notifies); graceful fallback if lib.nvim
-- absent. See `sessions.util.notify.create_titled` for the toast/title
-- behaviour this delegates to.
local _n
---@internal
---@return table
local function n()
  if not _n then
    _n = require("sessions.util.notify").create_titled("[sessions]")
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

composer.register_type("MARKS_MENU", {
  validate = function(raw)
    return true, raw, nil
  end,
  complete = function(lead)
    local out = {}
    for _, kind in ipairs(require("sessions.marks.menu").KINDS) do
      if lead == "" or kind:sub(1, #lead) == lead then
        out[#out + 1] = kind
      end
    end
    return out
  end,
})

---@internal
---Every `marks` route runs through this: the feature is opt-in, and a host
---that has not turned it on gets told so in one line.
---@return boolean
local function marks_enabled()
  local cfg = require("sessions.config").get()
  if cfg.marks and cfg.marks.enable then
    return true
  end
  n().warn("marks are off -- set `marks = { enable = true }` in setup()")
  return false
end

---@internal
---@param name string|nil
---@see sessions.core
local function do_save(name)
  local ok, res, stale = require("sessions.core").save(name)
  if ok then
    -- The chip (when active) already shows this persistently and pulses on
    -- exactly this event -- only one session-status indicator at a time.
    if not require("sessions.chip").is_active() then
      n().info("saved: " .. (res or "?"))
    end
    if stale and #stale > 0 then
      n().warn("dropped (file no longer exists): " .. table.concat(stale, ", "))
    end
    require("sessions.chip").refresh()
    require("sessions.chip").pulse()
  else
    n().error("save failed: " .. (res or "?"))
  end
end

---@internal
---@param name string|nil
---@see sessions.core
local function do_load(name)
  local ok, res, hidden, stale = require("sessions.core").load(name)
  if ok then
    if not require("sessions.chip").is_active() then
      n().info("loaded: " .. (res or "?"))
    end
    if hidden and #hidden > 0 then
      n().info("hidden (unsaved): " .. table.concat(hidden, ", "))
    end
    if stale and #stale > 0 then
      n().warn("dropped (file no longer exists): " .. table.concat(stale, ", "))
    end
    require("sessions.chip").refresh()
    require("sessions.chip").pulse()
  else
    n().error("load failed: " .. (res or "?"))
  end
end

---@class Sessions.StaleEntry
---@field name string
---@field path string
---@field meta Sessions.Meta

---@internal
---Every saved session whose own recorded `cwd`/`branch` (written at save
---time by `core.save()`, whenever `branch_aware`/`project_aware` were on)
---no longer add up to a real, checkoutable branch -- see
---`sessions.git.branch_exists()`'s own doc comment for exactly what counts
---as confidently gone (filesystem-only: no external `git` process to fail
---ambiguously). A session with no recorded `branch`/`cwd` at all (custom
---name, or saved with both `*_aware` options off) is never a candidate --
---there is nothing to re-check it against.
---@return Sessions.StaleEntry[]
local function find_stale()
  local core = require("sessions.core")
  local git = require("sessions.git")
  local out = {}
  for _, path in ipairs(core.list()) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    local meta = core.metadata(name)
    if meta and meta.branch and meta.cwd then
      if not git.branch_exists(meta.cwd, meta.branch) then
        out[#out + 1] = { name = name, path = path, meta = meta }
      end
    end
  end
  return out
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
            require("sessions.chip").refresh()
          else
            n().error("delete failed: " .. (res or "?"))
          end
        end,
      },

      {
        path = { "stale" },
        desc = "List saved sessions whose recorded branch no longer exists",
        run = function()
          local stale = find_stale()
          if #stale == 0 then
            n().info("No stale sessions.")
            return
          end
          local lines = {}
          for _, s in ipairs(stale) do
            lines[#lines + 1] = s.name .. "  [" .. s.meta.branch .. "]  " .. s.meta.cwd
          end
          n().info(table.concat(lines, "\n"))
        end,
      },

      {
        path = { "delete-stale" },
        desc = "Delete every stale session (see :Session stale), one confirm for the whole batch",
        run = function()
          local stale = find_stale()
          if #stale == 0 then
            n().info("No stale sessions.")
            return
          end
          -- Ask once for the whole batch, not once per session -- same
          -- pattern ui.tabline's close_all_bufs/close_bufs use for "discard
          -- changes in N modified buffers?".
          local names = {}
          for _, s in ipairs(stale) do
            names[#names + 1] = s.name
          end
          local choice = vim.fn.confirm(
            ("Delete %d stale session(s)?\n\n%s"):format(#stale, table.concat(names, "\n")),
            "&Yes\n&No",
            2
          )
          if choice ~= 1 then
            return
          end
          local deleted, failed = {}, {}
          for _, s in ipairs(stale) do
            local ok = require("sessions.core").delete(s.name)
            if ok then
              deleted[#deleted + 1] = s.name
            else
              failed[#failed + 1] = s.name
            end
          end
          if #deleted > 0 then
            n().info("deleted: " .. table.concat(deleted, ", "))
            require("sessions.chip").refresh()
          end
          if #failed > 0 then
            n().error("failed to delete: " .. table.concat(failed, ", "))
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
            require("sessions.chip").refresh()
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

      {
        path = { "chip-toggle" },
        desc = "Show/hide the corner chip on demand",
        run = function()
          require("sessions.chip").toggle()
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
          local ok, res, stale = require("sessions.core").load_tab(ctx.args.name)
          if ok then
            n().info("tab session loaded: " .. (res or "?"))
            if stale and #stale > 0 then
              n().warn("dropped (file no longer exists): " .. table.concat(stale, ", "))
            end
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

      -- The mark list (sessions.marks). Registered whether or not
      -- `marks.enable` is on: a disabled feature answers with one line
      -- saying so, rather than "unknown subcommand".
      {
        path = { "marks" },
        desc = "Open the mark list in the configured picker",
        run = function()
          if marks_enabled() then
            require("sessions.marks.menu").open()
          end
        end,
      },
      {
        path = { "marks", "menu" },
        args = { { name = "kind", type = "MARKS_MENU", optional = true } },
        desc = "Open the mark list: auto|edit|kit|snacks|telescope|fzf",
        run = function(ctx)
          if marks_enabled() then
            require("sessions.marks.menu").open(ctx.args.kind)
          end
        end,
      },
      {
        path = { "marks", "add" },
        args = { { name = "path", type = "FILE", optional = true } },
        flags = {
          { name = "front", short = "f", bool = true },
          { name = "permanent", short = "p", bool = true },
        },
        desc = "Add a file to the list (default: current buffer, appended)",
        run = function(ctx)
          if not marks_enabled() then
            return
          end
          local ok, err = require("sessions.marks").add(ctx.args.path, {
            front = ctx.flags.front == true,
            permanent = ctx.flags.permanent == true,
          })
          if not ok then
            n().warn("marks add: " .. tostring(err))
          elseif err then
            n().info("marks: " .. err)
          else
            n().info("marks: added")
          end
        end,
      },
      {
        path = { "marks", "remove" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "Remove a file from the list (default: current buffer)",
        run = function(ctx)
          if not marks_enabled() then
            return
          end
          local ok, err = require("sessions.marks").remove(ctx.args.path)
          if ok then
            n().info("marks: removed")
          else
            n().warn("marks remove: " .. tostring(err))
          end
        end,
      },
      {
        path = { "marks", "pin" },
        args = { { name = "path", type = "FILE", optional = true } },
        flags = { { name = "front", short = "f", bool = true } },
        desc = "Pin a file: a default that survives `defaults reset`",
        run = function(ctx)
          if not marks_enabled() then
            return
          end
          local ok, err = require("sessions.marks").pin(ctx.args.path, {
            front = ctx.flags.front == true,
          })
          if not ok then
            n().warn("marks pin: " .. tostring(err))
          else
            n().info("marks: " .. (err or "pinned"))
          end
        end,
      },
      {
        path = { "marks", "unpin" },
        args = { { name = "path", type = "FILE", optional = true } },
        desc = "Stop treating a file as a default (the list entry stays)",
        run = function(ctx)
          if not marks_enabled() then
            return
          end
          local ok, err = require("sessions.marks").unpin(ctx.args.path)
          if ok then
            n().info("marks: unpinned")
          else
            n().warn("marks unpin: " .. tostring(err))
          end
        end,
      },
      {
        path = { "marks", "defaults", "sync" },
        desc = "Append every missing default and pin; the rest stays",
        run = function()
          if marks_enabled() then
            local added = require("sessions.marks").defaults_sync()
            n().info(("marks: %d default(s) added"):format(added))
          end
        end,
      },
      {
        path = { "marks", "defaults", "reset" },
        desc = "Rebuild the list from the defaults and pins, in that order",
        run = function()
          if marks_enabled() then
            local count = require("sessions.marks").defaults_reset()
            n().info(("marks: reset to %d default(s)"):format(count))
          end
        end,
      },
      {
        path = { "marks", "select" },
        args = { { name = "index", type = "INT" } },
        desc = "Jump to mark <index>",
        run = function(ctx)
          if not marks_enabled() then
            return
          end
          local ok, err = require("sessions.marks").select(ctx.args.index)
          if not ok then
            n().warn("marks: " .. tostring(err))
          end
        end,
      },
      {
        path = { "marks", "preview" },
        args = { { name = "index", type = "INT" } },
        desc = "Read-only preview of mark <index> (q closes)",
        run = function(ctx)
          if not marks_enabled() then
            return
          end
          local ok, err = require("sessions.marks.preview").open_index(ctx.args.index)
          if not ok and err then
            n().warn("marks: " .. err)
          end
        end,
      },
      {
        path = { "marks", "list" },
        desc = "Print the list",
        run = function()
          if marks_enabled() then
            n().info(table.concat(require("sessions.marks").debug_lines(), "\n"))
          end
        end,
      },
      {
        path = { "marks", "debug" },
        desc = "Dump the list, its scope and its store into a scratch buffer",
        run = function()
          if not marks_enabled() then
            return
          end
          local lines = require("sessions.marks").debug_lines()
          vim.cmd("new")
          vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
          vim.bo.buftype = "nofile"
          vim.bo.bufhidden = "wipe"
          vim.bo.swapfile = false
          vim.bo.modifiable = false
        end,
      },
      {
        path = { "marks", "import-harpoon" },
        args = { { name = "bucket", type = "STRING", optional = true } },
        desc = "Take over a harpoon v2 list (bucket defaults to stdpath('config'))",
        run = function(ctx)
          if not marks_enabled() then
            return
          end
          local count, err = require("sessions.marks").import_harpoon({ bucket = ctx.args.bucket })
          if err then
            n().warn("marks import: " .. err)
          else
            n().info(
              ("marks: %d entr%s imported from harpoon"):format(count, count == 1 and "y" or "ies")
            )
          end
        end,
      },
    },
  })

  -- :LastSession — a plain zero-arg command (not a :Session subcommand) so it
  -- works as `nvim +LastSession` on the CLI. Loads the `default_name`
  -- ("last") session, which every exit rewrites (`save_last`, see
  -- core.save_last): the editor as it was when you last quit, whatever
  -- project or branch that was and whether or not you ever saved.
  --
  -- It used to hardcode "last" on the theory that autosave wrote there, then
  -- switched to the bare `:Session load` resolution once autosave went
  -- per-project -- which left "last" (and so `+LastSession`) stale unless you
  -- saved by hand. The exit snapshot makes the literal name right again. It
  -- falls back to that same resolution when there is no "last" yet (fresh
  -- install) or `save_last` is switched off.
  require("lib.nvim.bindings.usercmd").create("LastSession", function()
    local cfg = require("sessions.config").cfg
    if
      cfg.save_last and vim.fn.filereadable(cfg.root .. "/" .. cfg.default_name .. ".vim") == 1
    then
      do_load(cfg.default_name)
    else
      do_load(nil)
    end
  end, { desc = "Load the session you left on exit (nvim +LastSession)" })

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
