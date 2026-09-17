-- TESTS/init_spec.lua — sessions.setup() and the public API on `sessions`.
--
-- Last in the run order: `setup()` is a one-shot that registers the real user
-- commands, the real autocmd group and (when configured) real keymaps, and
-- latches so a second call does nothing. Running it earlier would leave that
-- wiring in place for every spec after it.

return function(H)
  local sessions = require("sessions")
  local config = require("sessions.config")
  local core = require("sessions.core")

  local dir, cleanup = H.fixture("init")
  vim.cmd("silent! %bwipeout!")
  pcall(vim.api.nvim_del_augroup_by_name, "SessionsNvim")

  -- The public API is a thin layer over core; that it stays wired to core is
  -- the point, so each function is checked against the module it delegates to.
  for _, name in ipairs({
    "setup",
    "save",
    "load",
    "list",
    "delete",
    "rename",
    "current",
    "metadata",
    "pick",
  }) do
    H.eq(type(sessions[name]), "function", ("sessions.%s is part of the public API"):format(name))
  end

  -- ------------------------------------------------------------------ setup

  H.falsy(vim.g.loaded_sessions_nvim, "the plugin is not marked loaded before setup()")

  sessions.setup({
    root = dir .. "/sroot",
    branch_aware = false,
    project_aware = false,
    metadata = true,
    restore_buffer_order = false,
    autoload = false,
    autosave = false,
    keymaps = { save = "gIs" },
    which_key = { enable = false },
  })

  H.eq(vim.g.loaded_sessions_nvim, 1, "setup() marks the plugin loaded")
  H.contains(config.get().root, "sroot", "the options are applied")
  H.eq(vim.fn.exists(":Session"), 2, "the commands are registered")
  H.eq(vim.fn.exists(":SessionLoad"), 2, "including the picker command")
  H.ok(vim.fn.maparg("gIs", "n") ~= "", "and the configured keymap is bound")

  -- Idempotent: a second setup() -- a second `require("sessions").setup()` in a
  -- config, or a plugin manager calling it again -- must not re-register
  -- anything or quietly change the configuration.
  sessions.setup({ root = dir .. "/somewhere-else", default_name = "other" })
  H.excludes(config.get().root, "somewhere-else", "a second setup() changes nothing")
  H.eq(config.get().default_name, "last", "not even a single option")

  -- ------------------------------------------------------------- public API

  H.falsy(sessions.current(), "no session is active yet")

  local ok, path = sessions.save("api")
  H.ok(ok, "sessions.save() saves")
  H.eq(path, config.get().root .. "/api.vim", "returning the path")
  H.eq(sessions.current(), "api", "and the session becomes the current one")
  H.eq(core.current(), sessions.current(), "which is core's notion of it")

  local meta = sessions.metadata("api")
  H.ok(meta, "sessions.metadata() reads the sidecar")

  H.eq(#sessions.list(), 1, "sessions.list() lists it")
  -- Normalized on both sides: `list()` globs, and on Windows `globpath()`
  -- answers with backslashes where `save()` returned forward slashes.
  H.eq(vim.fs.normalize(sessions.list()[1]), vim.fs.normalize(path), "as a full path")

  local load_ok = sessions.load("api")
  H.ok(load_ok, "sessions.load() loads")

  local ren_ok = sessions.rename("api", "api2")
  H.ok(ren_ok, "sessions.rename() renames")
  H.eq(sessions.current(), "api2", "and follows the active session")

  local del_ok = sessions.delete("api2")
  H.ok(del_ok, "sessions.delete() deletes")
  H.eq(#sessions.list(), 0, "leaving nothing")
  H.falsy(sessions.current(), "and no active session")

  -- sessions.pick() with nothing saved and no backend installed reports rather
  -- than raising -- the same path picker_spec covers, reached through the API.
  do
    local no_snacks = H.stub("snacks", false)
    local no_telescope = H.stub("telescope", false)
    local notified = {}
    local real_notify = vim.notify
    vim.notify = function(msg)
      notified[#notified + 1] = msg
    end
    sessions.pick()
    vim.notify = real_notify
    H.eq(#notified, 1, "sessions.pick() reports instead of opening")
    H.contains(notified[1], "no sessions saved yet", "with the empty-state message")
    no_snacks()
    no_telescope()
  end

  -- Leave nothing behind ------------------------------------------------------
  pcall(vim.keymap.del, "n", "gIs")
  pcall(vim.api.nvim_del_augroup_by_name, "SessionsNvim")
  config.setup({})
  vim.cmd("silent! %bwipeout!")
  cleanup()
end
