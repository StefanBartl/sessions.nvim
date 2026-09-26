-- TESTS/autocmds_spec.lua — sessions.bindings.autocmds: the VimEnter autoload,
-- the VimLeavePre autosave, and the structural autocmds behind the statusline's
-- dirty marker.
--
-- Fired with `nvim_exec_autocmds` rather than by calling the callbacks, so the
-- registration itself -- event, group, `once`, and the conditions each handler
-- checks -- is part of what is asserted. `ui.kit` is stubbed in one direction
-- only: it is genuinely not installed here, so the hand-rolled fallback is the
-- default path and the ui.nvim path is the one that needs standing up.

return function(H)
  local config = require("sessions.config")
  local core = require("sessions.core")

  local dir, cleanup = H.fixture("autocmds")
  vim.cmd("silent! %bwipeout!")

  ---@param extra table|nil
  local function setup(extra)
    config.setup(vim.tbl_deep_extend("force", {
      root = dir .. "/sroot",
      branch_aware = false,
      project_aware = false,
      metadata = false,
      restore_buffer_order = false,
      autoload = false,
      autosave = false,
    }, extra or {}))
  end

  ---Load the module with whatever stubs are in place right now; it resolves
  ---lib.nvim/ui.nvim once, at load time.
  ---@return table
  local function load_module()
    return H.fresh("sessions.bindings.autocmds")
  end

  ---Every autocmd in the plugin's group.
  ---@return table[]
  local function registered()
    local ok, list = pcall(vim.api.nvim_get_autocmds, { group = "SessionsNvim" })
    return ok and list or {}
  end

  ---@param event string
  ---@return integer
  local function count(event)
    local n = 0
    for _, a in ipairs(registered()) do
      if a.event == event then
        n = n + 1
      end
    end
    return n
  end

  -- ------------------------------------------------- everything switched off

  setup()
  load_module().enable()
  H.eq(#registered(), 0, "with autoload and autosave off, nothing is registered")

  -- ----------------------------------------------------------------- autosave

  setup({ autosave = true })
  load_module().enable()
  H.eq(count("VimLeavePre"), 1, "autosave registers one VimLeavePre autocmd")
  H.ok(count("BufAdd") > 0, "and the structural dirty-tracking autocmds")
  H.ok(count("WinClosed") > 0, "for windows as well as buffers")

  -- The dirty marker, driven by a real event rather than by calling
  -- core.mark_dirty() directly.
  H.ok(core.save("dirtycheck"), "a session is active")
  H.falsy(core.dirty(), "and clean")
  vim.api.nvim_exec_autocmds("BufAdd", {})
  H.ok(core.dirty(), "a structural change marks it dirty")

  -- autosave_name = true resolves a name the way a bare `:Session save` does,
  -- rather than writing every project into one shared slot.
  core.delete("dirtycheck")
  local git_stub = H.stub("sessions.git", {
    resolve_name = function()
      return "resolved-by-git"
    end,
    current_branch = function()
      return nil
    end,
  })
  setup({ autosave = true, autosave_name = true, branch_aware = true })
  load_module().enable()
  vim.api.nvim_exec_autocmds("VimLeavePre", {})
  H.eq(
    vim.fn.filereadable(config.get().root .. "/resolved-by-git.vim"),
    1,
    "autosave_name = true saves under the auto-resolved name"
  )
  git_stub()

  -- A string pins autosave to one fixed name regardless of project/branch.
  setup({ autosave = true, autosave_name = "pinned" })
  load_module().enable()
  vim.api.nvim_exec_autocmds("VimLeavePre", {})
  H.eq(vim.fn.filereadable(config.get().root .. "/pinned.vim"), 1, "a string pins the name")

  -- And `false` disables autosave even though `autosave` itself is on -- the
  -- dirty tracking stays, which is what the statusline marker needs.
  setup({ autosave = true, autosave_name = false })
  load_module().enable()
  local before = #core.list()
  vim.api.nvim_exec_autocmds("VimLeavePre", {})
  H.eq(#core.list(), before, "autosave_name = false writes nothing on exit")
  H.ok(count("BufAdd") > 0, "while the dirty tracking is still registered")

  -- ----------------------------------------------------------------- autoload

  -- The group is cleared on every enable(), so a re-`setup()` cannot end up
  -- with two autoloads racing each other.
  setup({ autoload = true, autosave = true })
  load_module().enable()
  H.eq(count("VimEnter"), 1, "autoload registers exactly one VimEnter autocmd")
  load_module().enable()
  H.eq(count("VimEnter"), 1, "and enabling again replaces it rather than adding a second")

  local vim_enter = nil
  for _, a in ipairs(registered()) do
    if a.event == "VimEnter" then
      vim_enter = a
    end
  end
  H.ok(vim_enter, "the autoload autocmd is in the plugin's group")
  ---@cast vim_enter -nil
  H.ok(vim_enter.once, "and fires only once")

  -- Firing it restores the remembered session.
  H.ok(core.save("autoloaded"), "the session to autoload exists")
  require("sessions.state").set_last_loaded(config.get(), "autoloaded")
  vim.cmd("silent! %bwipeout!")

  local loaded_notices = {}
  local restore_notify = H.stub("lib.nvim.notify", {
    create = function()
      return {
        info = function(msg)
          loaded_notices[#loaded_notices + 1] = tostring(msg)
        end,
        warn = function() end,
        error = function() end,
      }
    end,
  })
  setup({ autoload = true, autosave = true })
  load_module().enable()
  vim.api.nvim_exec_autocmds("VimEnter", {})
  H.eq(core.current(), "autoloaded", "VimEnter autoloads the remembered session")
  H.eq(#loaded_notices, 1, "and says so once")
  H.contains(loaded_notices[1], "autoloaded: ", "naming what it restored")

  -- ------------------------------------------------------- autoload = "ask"

  do
    -- ui.nvim is not installed here, so the module's own `pcall(require,
    -- "ui.kit")` normally fails and the hand-rolled float answers. With a stub
    -- in place at load time, the ui.kit path runs instead.
    local asked = {}
    local answer = true
    local restore_kit = H.stub("ui.kit", {
      confirm = function(opts)
        asked[#asked + 1] = opts.question
        opts.on_answer(answer)
      end,
    })

    setup({ autoload = "ask", autosave = false })
    load_module().enable()

    core.delete("autoloaded")
    H.ok(core.save("asked"))
    require("sessions.state").set_last_loaded(config.get(), "asked")
    vim.cmd("silent! %bwipeout!")

    vim.api.nvim_exec_autocmds("VimEnter", {})
    H.eq(#asked, 1, 'autoload = "ask" asks before restoring anything')
    H.contains(asked[1], "Restore session 'asked'?", "naming the session it would restore")
    H.eq(core.current(), "asked", "and a yes restores it")

    -- A no restores nothing. The observable is the notification: `core.save`
    -- makes its session the current one, so `current()` cannot tell a restore
    -- from the save that set it up.
    answer = false
    core.delete("asked")
    H.ok(core.save("declinable"))
    require("sessions.state").set_last_loaded(config.get(), "declinable")
    local notices_before = #loaded_notices
    load_module().enable()
    vim.api.nvim_exec_autocmds("VimEnter", {})
    H.eq(#asked, 2, "the question is asked again")
    H.eq(#loaded_notices, notices_before, "and a no restores nothing")

    -- Nothing to restore: no question is asked at all.
    asked = {}
    for _, p in ipairs(core.list()) do
      core.delete(vim.fn.fnamemodify(p, ":t:r"))
    end
    require("sessions.state").set_last_loaded(config.get(), "gone")
    load_module().enable()
    vim.api.nvim_exec_autocmds("VimEnter", {})
    H.eq(#asked, 0, "with nothing saved, no question is asked")

    restore_kit()
  end

  -- ----------------------------------------- autoload = "ask", no ui.nvim

  do
    -- The fallback float: a real window with real buffer-local keymaps, driven
    -- by real keystrokes.
    local no_kit = H.stub("ui.kit", false)
    setup({ autoload = "ask", autosave = false })
    load_module().enable()

    H.ok(core.save("hand-rolled"))
    require("sessions.state").set_last_loaded(config.get(), "hand-rolled")
    vim.cmd("silent! %bwipeout!")

    local notices_before = #loaded_notices
    local wins_before = #vim.api.nvim_list_wins()
    vim.api.nvim_exec_autocmds("VimEnter", {})
    H.eq(#vim.api.nvim_list_wins(), wins_before + 1, "a float is opened to ask")

    local float = vim.api.nvim_get_current_win()
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float), 0, -1, false)
    H.contains(lines[1], "Restore session 'hand-rolled'?", "the float asks the question")
    H.contains(lines[2], "[y]es / [n]o", "and offers the two answers")

    -- `n` closes it and restores nothing.
    vim.api.nvim_feedkeys("n", "x", false)
    H.eq(#vim.api.nvim_list_wins(), wins_before, "answering closes the float")
    H.eq(#loaded_notices, notices_before, "and a no restores nothing")

    -- `y` restores.
    load_module().enable()
    vim.api.nvim_exec_autocmds("VimEnter", {})
    vim.api.nvim_feedkeys("y", "x", false)
    H.eq(#vim.api.nvim_list_wins(), wins_before, "the float is closed again")
    H.eq(#loaded_notices, notices_before + 1, "and a yes restores the session")
    H.eq(core.current(), "hand-rolled", "which is the remembered one")

    no_kit()
  end

  -- -------------------------------------------------------------- notify_title

  do
    -- Dedicated to this module's own notifier: it is built once at
    -- module-load time (unlike bindings/usercmds' lazily-memoized `n()` --
    -- see that module's own comment), and the shared `loaded_notices` stub
    -- above never captures `opts`, so exercise the title enrichment with a
    -- recorder that does.
    restore_notify()

    local seen
    local function stub_notify()
      return H.stub("lib.nvim.notify", {
        create = function(prefix)
          local rec = {}
          for _, level in ipairs({ "info", "warn", "error" }) do
            rec[level] = function(msg, opts)
              seen[#seen + 1] = { prefix = prefix, msg = msg, opts = opts }
            end
          end
          return rec
        end,
      })
    end

    -- Default: a title, for rich notify backends to key off of.
    seen = {}
    local restore1 = stub_notify()
    setup({ autoload = true, autosave = false })
    H.ok(core.save("titlecheck"))
    require("sessions.state").set_last_loaded(config.get(), "titlecheck")
    vim.cmd("silent! %bwipeout!")
    load_module().enable()
    vim.api.nvim_exec_autocmds("VimEnter", {})
    H.eq(#seen, 1, "one notification")
    H.eq(seen[1].opts and seen[1].opts.title, "Sessions", "a title is attached")
    restore1()

    -- notify_title = false: no opts at all, calling exactly as before.
    seen = {}
    local restore2 = stub_notify()
    core.delete("titlecheck")
    setup({ autoload = true, autosave = false, notify_title = false })
    H.ok(core.save("titlecheck2"))
    require("sessions.state").set_last_loaded(config.get(), "titlecheck2")
    vim.cmd("silent! %bwipeout!")
    load_module().enable()
    vim.api.nvim_exec_autocmds("VimEnter", {})
    H.eq(#seen, 1, "one notification")
    H.falsy(seen[1].opts, "notify_title = false attaches no opts at all")
    restore2()

    core.delete("titlecheck2")
  end

  -- -------------------------------------------------- chip active: notify skipped

  do
    -- While the chip is actually mounted (ensure_mounted() runs at the top of
    -- enable()), autoload's own "autoloaded:" notify is skipped entirely --
    -- only one session-status indicator at a time.
    restore_notify()
    local seen = {}
    local restore3 = H.stub("lib.nvim.notify", {
      create = function()
        local rec = {}
        for _, level in ipairs({ "info", "warn", "error" }) do
          rec[level] = function(msg)
            seen[#seen + 1] = { level = level, msg = tostring(msg) }
          end
        end
        return rec
      end,
    })
    local refreshed, pulsed = {}, {}
    local restore_kit = H.stub("ui.kit", {
      chip = {
        mount = function() end,
        refresh = function(id)
          refreshed[#refreshed + 1] = id
        end,
        pulse = function(_id, opts)
          pulsed[#pulsed + 1] = opts
        end,
      },
    })

    setup({ autoload = true, autosave = false })
    H.ok(core.save("chipcheck"))
    require("sessions.state").set_last_loaded(config.get(), "chipcheck")
    vim.cmd("silent! %bwipeout!")
    package.loaded["sessions.chip"] = nil
    load_module().enable()
    H.ok(require("sessions.chip").is_active(), "chip actually mounted with ui.kit stubbed")

    vim.api.nvim_exec_autocmds("VimEnter", {})
    H.eq(#seen, 0, "no notify at all -- the chip already shows/pulses this")
    H.ok(#refreshed > 0 and #pulsed > 0, "but the chip was refreshed and pulsed")

    core.delete("chipcheck")
    restore_kit()
    restore3()
    package.loaded["sessions.chip"] = nil
  end

  restore_notify()

  -- Leave nothing behind ------------------------------------------------------
  pcall(vim.api.nvim_del_augroup_by_name, "SessionsNvim")
  for _, p in ipairs(core.list()) do
    core.delete(vim.fn.fnamemodify(p, ":t:r"))
  end
  H.falsy(core.current(), "no session stays active")

  package.loaded["sessions.bindings.autocmds"] = nil
  config.setup({})
  vim.cmd("silent! %bwipeout!")
  cleanup()
end
