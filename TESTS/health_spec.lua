-- TESTS/health_spec.lua — sessions.health: the `:checkhealth sessions` report.
--
-- A reporter has no return value, so the assertions are about what it reports.
-- `vim.health` is replaced with a recorder for the duration, which also keeps
-- the report out of whatever buffer a real :checkhealth would be writing into
-- and makes each branch assertable by simply removing a dependency.

return function(H)
  local config = require("sessions.config")

  local dir, cleanup = H.fixture("health")

  local real_health = vim.health
  local entries = {} ---@type { kind: string, msg: string }[]

  ---@return string  # the whole report as one string
  local function report()
    local out = {}
    for i, e in ipairs(entries) do
      out[i] = e.kind .. ": " .. e.msg
    end
    return table.concat(out, "\n")
  end

  ---@param kind string
  ---@param needle string
  ---@return boolean
  local function reported(kind, needle)
    for _, e in ipairs(entries) do
      if e.kind == kind and e.msg:find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  local recorder = {}
  for _, kind in ipairs({ "start", "ok", "info", "warn", "error" }) do
    recorder[kind] = function(msg)
      entries[#entries + 1] = { kind = kind, msg = tostring(msg) }
    end
  end
  vim.health = recorder

  ---Run the report from scratch.
  local function check()
    entries = {}
    require("sessions.health").check()
  end

  -- ------------------------------------------------- everything as installed

  config.setup({ root = dir .. "/not-created-yet" })
  check()

  H.ok(reported("start", "sessions.nvim"), "the report has a heading")
  H.ok(reported("ok", "Neovim >= 0.9"), "the Neovim version is checked")
  H.ok(reported("ok", "vim.json available"), "and vim.json")
  H.ok(reported("ok", "libuv available"), "and libuv")
  H.ok(reported("ok", "vim.system available"), "and vim.system")

  -- lib.nvim is a hard dependency for the commands; the suite cannot run
  -- without it, so this is always the "found" branch here.
  H.ok(reported("ok", "lib.nvim found"), "lib.nvim is reported as present")
  H.ok(reported("ok", "lib.nvim.notify available"), "and so are its submodules")
  H.ok(reported("ok", "lib.nvim.bindings.keymap available"))
  H.ok(reported("ok", "lib.nvim.git available"))

  -- The configuration section echoes the active config, which is what makes a
  -- health report useful in a bug report.
  H.ok(reported("info", "root: " .. config.get().root), "the configured root is shown")
  H.ok(reported("info", "default_name: last"), "and the default name")
  H.ok(reported("info", "branch_aware: true"), "and each switch")
  H.ok(reported("info", "session root does not exist yet"), "a root not yet created is noted")
  H.ok(reported("ok", "sessionoptions: "), "sessionoptions is echoed")

  -- ---------------------------------------------- optional plugins, absent

  -- None of these is installed in the test runtime, so this is the branch a
  -- fresh install actually reports.
  H.ok(reported("info", "ui.nvim not found"), "a missing ui.nvim is an info, not an error")
  H.ok(reported("info", "which-key not found"), "and so is a missing which-key")
  H.ok(
    reported("info", "neither snacks.nvim nor telescope.nvim found"),
    "and a missing picker backend explains what :SessionLoad needs"
  )

  -- ---------------------------------------------- optional plugins, present

  do
    local undo_snacks = H.stub("snacks", {})
    check()
    H.ok(reported("ok", "snacks.nvim found"), "an installed snacks.nvim is picked up")
    undo_snacks()

    local undo_telescope = H.stub("telescope", {})
    local no_snacks = H.stub("snacks", false)
    check()
    H.ok(reported("ok", "telescope.nvim found"), "telescope is the fallback backend")
    no_snacks()
    undo_telescope()

    local undo_kit = H.stub("ui.kit", {})
    check()
    H.ok(reported("ok", "ui.nvim found"), "an installed ui.nvim is picked up")
    undo_kit()
  end

  -- ------------------------------------------------- soft dependency missing

  do
    local no_notify = H.stub("lib.nvim.notify", false)
    check()
    H.ok(reported("info", "lib.nvim.notify not found"), "a missing notify falls back, not fails")
    no_notify()

    local no_git = H.stub("lib.nvim.git", false)
    check()
    H.ok(reported("info", "lib.nvim.git not found"), "and so does a missing git helper")
    no_git()
  end

  -- ------------------------------------------------- a root that does exist

  do
    local root = dir .. "/sroot"
    config.setup({
      root = root,
      branch_aware = false,
      project_aware = false,
      metadata = false,
      restore_buffer_order = false,
    })
    vim.cmd("silent! %bwipeout!")
    local core = require("sessions.core")
    H.ok(core.save("one"))
    H.ok(core.save("two"))

    check()
    H.ok(reported("ok", "session root exists: " .. config.get().root), "an existing root is ok")
    H.ok(reported("info", "2 session(s) stored"), "and the sessions in it are counted")

    core.delete("one")
    core.delete("two")
    H.falsy(core.current(), "the spec leaves no session active")
  end

  -- ------------------------------------------------------- commands section

  -- The command section reports on real `:Session`/`:LastSession`/`:SessionLoad`
  -- registrations. They are registered by usercmds_spec/init_spec, which run
  -- after this one, so this is the "not registered yet" branch -- the one a
  -- user who forgot `setup()` sees.
  check()
  local registered = vim.fn.exists(":Session") == 2
  H.eq(
    reported("ok", ":Session registered"),
    registered,
    "the command section reflects whether :Session actually exists"
  )
  H.ok(
    reported("ok", ":LastSession registered") or reported("info", ":LastSession not found"),
    ":LastSession is reported either way"
  )
  H.ok(
    reported("ok", ":SessionLoad registered") or reported("info", ":SessionLoad not found"),
    "and so is :SessionLoad"
  )

  -- An empty sessionoptions is a warning: a session saved with it stores
  -- nothing, which is worth flagging before the user loses a layout to it.
  config.setup({ root = dir, sessionoptions = "" })
  check()
  H.ok(reported("warn", "sessionoptions is empty"), "an empty sessionoptions warns")

  -- The report never raises, whatever it finds: a :checkhealth that throws is
  -- worse than one that reports a problem.
  H.ok(#report() > 0, "the report has content")

  vim.health = real_health
  config.setup({})
  cleanup()
end
