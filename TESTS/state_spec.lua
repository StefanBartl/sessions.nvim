-- TESTS/state_spec.lua — sessions.state: the one-pointer file that remembers
-- which session to resume.
--
-- Small, but load-bearing: `.state.json` is what a bare `:Session load` and
-- autoload fall back to when the project/branch name resolves to nothing they
-- have ever saved. It is also *global* -- one pointer shared by every project
-- -- which is why core.lua prefers the auto-resolved name over it (see
-- core_spec.lua's "resolve order" block).

---@diagnostic disable: missing-fields
-- The config tables below carry only `root`, the single field state.lua reads.

return function(H)
  local state = require("sessions.state")

  local dir, cleanup = H.fixture("state")
  local cfg = { root = dir }
  local path = dir .. "/.state.json"

  -- Nothing written yet -------------------------------------------------------
  -- A fresh install has no state file, and reading one must be an ordinary
  -- "nothing remembered" rather than an error.
  local empty = state.read(cfg)
  H.eq(type(empty), "table", "reading a missing state file yields a table")
  H.falsy(empty.last_loaded, "with nothing remembered in it")

  -- Round-trip ----------------------------------------------------------------
  state.set_last_loaded(cfg, "alpha")
  H.eq(vim.fn.filereadable(path), 1, "the state file is written into cfg.root")
  H.eq(state.read(cfg).last_loaded, "alpha", "and reads back")

  -- One pointer, not a history: the second write replaces the first.
  state.set_last_loaded(cfg, "beta")
  H.eq(state.read(cfg).last_loaded, "beta", "a later save overwrites the pointer")
  local raw = H.read(path)
  H.excludes(raw, "alpha", "the previous value is gone from the file")

  -- Corrupt file --------------------------------------------------------------
  -- A half-written or hand-edited file must not take `:Session load` down with
  -- it; the session it points at is a convenience, not data the user typed.
  vim.fn.writefile({ "{ this is not json" }, path)
  local broken = state.read(cfg)
  H.eq(type(broken), "table", "unparseable state reads as an empty table")
  H.falsy(broken.last_loaded, "and remembers nothing")

  -- Valid JSON that is not an object is the same case.
  vim.fn.writefile({ "42" }, path)
  H.eq(type(state.read(cfg)), "table", "JSON that is not an object reads as an empty table")

  -- Unwritable root -----------------------------------------------------------
  -- `set_last_loaded` runs at the end of every save/load. A root that cannot
  -- be written (here: a path whose parent is a file) may fail, but not raise,
  -- or an otherwise successful save would report an error.
  local blocker = dir .. "/blocker"
  vim.fn.writefile({ "i am a file" }, blocker)
  local ok = pcall(state.set_last_loaded, { root = blocker .. "/nested" }, "gamma")
  H.ok(ok, "a root that cannot be written does not raise")

  cleanup()
end
