-- TESTS/usercmds_spec.lua — sessions.bindings.usercmds: the `:Session` verb,
-- `:LastSession` and `:SessionLoad`.
--
-- Driven through real `:` commands rather than by calling the route handlers,
-- so the argument parsing, the completion types and the notifications are all
-- part of what is asserted. Two things are replaced: `lib.nvim.notify`, which
-- becomes a recorder (the messages *are* the observable result of most
-- routes), and `vim.system`, because `toggle-track` is the one code path in
-- this plugin that genuinely shells out to git.

return function(H)
  local config = require("sessions.config")
  local core = require("sessions.core")

  local dir, cleanup = H.fixture("usercmds")
  vim.cmd("silent! %bwipeout!")
  config.setup({
    root = dir .. "/sroot",
    branch_aware = false,
    project_aware = false,
    metadata = true,
    restore_buffer_order = false,
  })
  local root = config.get().root

  -- The notifier is resolved once per module load and cached, so the stub goes
  -- in before the module is required.
  local said = {} ---@type { level: string, msg: string }[]
  local restore_notify = H.stub("lib.nvim.notify", {
    create = function()
      local rec = {}
      for _, level in ipairs({ "info", "warn", "error" }) do
        rec[level] = function(msg)
          said[#said + 1] = { level = level, msg = tostring(msg) }
        end
      end
      return rec
    end,
  })

  local usercmds = H.fresh("sessions.bindings.usercmds")

  ---The most recent message, as "level: text".
  ---@return string
  local function last()
    local e = said[#said]
    return e and (e.level .. ": " .. e.msg) or ""
  end

  ---@param n integer
  ---@return boolean
  local function wait_for_messages(n)
    return vim.wait(2000, function()
      return #said >= n
    end, 10)
  end

  -- -------------------------------------------------------------- registration

  usercmds.enable()
  H.eq(vim.fn.exists(":Session"), 2, ":Session is registered")
  H.eq(vim.fn.exists(":LastSession"), 2, ":LastSession too")
  H.eq(vim.fn.exists(":SessionLoad"), 2, "and :SessionLoad")

  -- ---------------------------------------------------------------- save/load

  vim.cmd("Session list")
  H.contains(last(), "No sessions saved.", "listing nothing says so")

  vim.cmd("Session current")
  H.contains(last(), "No session active.", "and so does asking for the active one")

  vim.cmd("Session save alpha")
  H.contains(last(), "info: saved: ", "saving reports the path it wrote")
  H.eq(vim.fn.filereadable(root .. "/alpha.vim"), 1, "and the session is on disk")

  vim.cmd("Session save-timestamp")
  local stamped = vim.fn.globpath(root, "sess-*.vim", false, true)
  H.eq(#stamped, 1, "save-timestamp writes a timestamped session")
  H.ok(
    vim.fn.fnamemodify(stamped[1], ":t:r"):match("^sess%-%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d$"),
    "named sess-YYYYMMDD-HHMMSS"
  )

  vim.cmd("Session current")
  H.contains(last(), "Current session: ", "the active session is reported by name")

  vim.cmd("Session list")
  H.contains(last(), "alpha", "listing names every session")
  H.contains(last(), "*", "and marks the active one")

  vim.cmd("Session load alpha")
  H.contains(last(), "info: loaded: ", "loading reports the file it sourced")
  H.eq(core.current(), "alpha", "and the session is active")

  vim.cmd("Session load no-such-session")
  H.contains(last(), "error: load failed: ", "loading something that is not there is an error")

  -- ------------------------------------------------------------- completion

  -- The SESSION/TAB_SESSION/LAYOUT argument types look their values up fresh
  -- on every request rather than snapshotting them at registration, because
  -- the set of sessions changes with every save and delete.
  local completions = vim.fn.getcompletion("Session load ", "cmdline")
  H.ok(vim.tbl_contains(completions, "alpha"), "a saved session completes")
  H.falsy(vim.tbl_contains(completions, "alpha.vim"), "as a name, not as a filename")

  vim.cmd("Session save alpha-two")
  local prefixed = vim.fn.getcompletion("Session load alpha-t", "cmdline")
  H.eq(table.concat(prefixed, ","), "alpha-two", "completion filters by what is typed so far")
  H.ok(
    vim.tbl_contains(vim.fn.getcompletion("Session ", "cmdline"), "save-timestamp"),
    "the subcommands complete as well"
  )

  -- --------------------------------------------------------- delete / rename

  vim.cmd("Session delete alpha-two")
  H.contains(last(), "info: deleted: alpha-two", "deleting reports the name")
  H.eq(vim.fn.filereadable(root .. "/alpha-two.vim"), 0, "and the file is gone")

  vim.cmd("Session delete no-such-session")
  H.contains(last(), "error: delete failed: ", "deleting what is not there is an error")

  vim.cmd("Session rename alpha renamed")
  H.contains(last(), "info: renamed ", "renaming reports both names")
  H.eq(vim.fn.filereadable(root .. "/renamed.vim"), 1, "and the file moved")

  vim.cmd("Session rename alpha renamed")
  H.contains(last(), "error: rename failed: ", "renaming a session that is gone is an error")

  -- ------------------------------------------------------------ tab sessions

  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  local tabs_before = #vim.api.nvim_list_tabpages()

  vim.cmd("Session save-tab work")
  H.contains(last(), "info: tab session saved: ", "save-tab reports the path")
  H.eq(vim.fn.filereadable(root .. "/.tabs/work.vim"), 1, "storing under .tabs/")
  H.ok(
    vim.tbl_contains(vim.fn.getcompletion("Session load-tab ", "cmdline"), "work"),
    "tab sessions complete from their own directory"
  )

  vim.cmd("Session load-tab work")
  H.contains(last(), "info: tab session loaded: ", "load-tab reports success")
  H.eq(#vim.api.nvim_list_tabpages(), tabs_before + 1, "in a new tab")
  vim.cmd("tabclose")

  vim.cmd("Session load-tab nope")
  H.contains(last(), "error: tab session load failed: ", "and reports a missing one")

  -- ----------------------------------------------------------------- layouts

  vim.cmd("Session save-layout split")
  H.contains(last(), "info: layout saved: ", "save-layout reports the path")
  H.ok(
    vim.tbl_contains(vim.fn.getcompletion("Session load-layout ", "cmdline"), "split"),
    "layouts complete from their own directory"
  )

  vim.cmd("Session load-layout split")
  H.contains(last(), "info: layout restored: ", "load-layout reports success")

  vim.cmd("Session load-layout nope")
  H.contains(last(), "error: layout restore failed: ", "and reports a missing one")

  -- --------------------------------------------------------------- :LastSession

  -- Same resolution as a bare `:Session load`: whatever a save/autosave last
  -- targeted, not the literal name "last".
  vim.cmd("Session load renamed") -- which is what the state file now points at
  vim.cmd("LastSession")
  H.contains(last(), "info: loaded: ", ":LastSession resumes the remembered session")
  H.eq(core.current(), "renamed", "which is the one that was saved most recently")

  -- ---------------------------------------------------------- :SessionLoad

  do
    local no_snacks = H.stub("snacks", false)
    local no_telescope = H.stub("telescope", false)
    local notified = {}
    local real_notify = vim.notify
    vim.notify = function(msg)
      notified[#notified + 1] = msg
    end
    vim.cmd("SessionLoad")
    vim.notify = real_notify
    H.eq(#notified, 1, ":SessionLoad goes to the picker")
    H.contains(notified[1], "requires snacks.nvim", "which says what it needs")
    no_snacks()
    no_telescope()
  end

  -- --------------------------------------------------------------- toggle-track

  do
    -- Not a session that exists.
    said = {}
    usercmds.toggle_track("nothing-here")
    H.contains(last(), "error: session file not found: ", "toggling an absent session is an error")

    -- A root outside any git repository. The fixture root is inside this very
    -- checkout, so the upward `.git` search would always succeed here -- the
    -- search itself is what gets replaced, not the repository.
    said = {}
    local real_find = vim.fs.find
    vim.fs.find = function()
      return {}
    end
    usercmds.toggle_track("renamed")
    vim.fs.find = real_find
    H.contains(last(), "not inside a git repo", "a root outside git explains why it cannot work")

    -- The git calls themselves. Both are captured; neither runs.
    local calls = {}
    local real_system = vim.system
    local ls_stdout = "H TESTS/session.vim"
    local exit_code = 0
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, opts, on_exit)
      calls[#calls + 1] = { cmd = cmd, cwd = opts and opts.cwd }
      if cmd[2] == "ls-files" then
        on_exit({ code = 0, stdout = ls_stdout })
      else
        on_exit({ code = exit_code, stdout = "" })
      end
      return { wait = function() end }
    end

    said = {}
    usercmds.toggle_track("renamed")
    H.ok(wait_for_messages(1), "the git result is reported")
    H.eq(#calls, 2, "two git calls: one to read the flag, one to set it")
    H.eq(calls[1].cmd[2], "ls-files", "the first reads the current state")
    H.contains(
      table.concat(calls[2].cmd, " "),
      "--skip-worktree",
      "an untracked-flag file gets set"
    )
    H.contains(last(), "marked as skip-worktree", "and that is what is reported")

    -- `S` in `git ls-files -v` output means skip-worktree is already set, so
    -- the toggle goes the other way.
    calls, said, ls_stdout = {}, {}, "S TESTS/session.vim"
    usercmds.toggle_track("renamed")
    H.ok(wait_for_messages(1), "the second git result is reported")
    H.contains(
      table.concat(calls[2].cmd, " "),
      "--no-skip-worktree",
      "an already-skipped file gets un-skipped"
    )
    H.contains(last(), "is now tracked in git", "and that is what is reported")

    -- A failing git call is reported as such rather than silently ignored.
    calls, said, exit_code = {}, {}, 1
    usercmds.toggle_track("renamed")
    H.ok(wait_for_messages(1), "a failure is reported too")
    H.contains(last(), "error: git command failed", "as an error")
    exit_code = 0

    -- No name: the active session, else default_name.
    calls, said = {}, {}
    usercmds.toggle_track(nil)
    H.ok(wait_for_messages(1), "a nameless toggle reports as well")
    H.contains(
      table.concat(calls[1].cmd, " "),
      "renamed.vim",
      "toggle-track with no argument uses the active session"
    )

    -- Neovim < 0.10 has no vim.system: the blocking fallback runs instead.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = nil
    local argv = {}
    local restore_argv = H.stub("lib.nvim.cross.run_argv", {
      run_blocking_captured = function(args)
        argv[#argv + 1] = args
        return true, "S TESTS/session.vim"
      end,
      run_blocking = function(args)
        argv[#argv + 1] = args
        return true
      end,
    })
    said = {}
    usercmds.toggle_track("renamed")
    H.eq(#argv, 2, "the fallback makes the same two calls")
    H.contains(table.concat(argv[1], " "), "ls-files", "reading the flag first")
    H.contains(table.concat(argv[2], " "), "--no-skip-worktree", "then toggling it")
    H.contains(last(), "is now tracked in git", "reporting synchronously")
    restore_argv()

    -- Without vim.system *and* without lib.nvim's runner there is nothing left
    -- to run git with, and saying so beats doing nothing.
    local no_argv = H.stub("lib.nvim.cross.run_argv", false)
    said = {}
    usercmds.toggle_track("renamed")
    H.contains(last(), "vim.system() unavailable", "the last-resort case explains itself")
    no_argv()

    vim.system = real_system
  end

  -- Leave nothing behind ------------------------------------------------------
  for _, p in ipairs(core.list()) do
    core.delete(vim.fn.fnamemodify(p, ":t:r"))
  end
  H.falsy(core.current(), "no session stays active")

  restore_notify()
  -- Drop the module so a later spec re-requires it with the real notifier.
  package.loaded["sessions.bindings.usercmds"] = nil
  config.setup({})
  vim.cmd("silent! %bwipeout!")
  cleanup()
end
