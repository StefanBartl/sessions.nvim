-- Test code: when something here comes back nil -- a `pcall(require, ...)`,
-- a fixture read, a uv handle -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure it exists to report.
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields
-- The config and meta tables below carry only the fields the function under
-- test reads; a resolved Sessions.Config per case would be noise.
-- TESTS/meta_spec.lua — sessions.meta: the sidecar file that carries whatever
-- a session file itself cannot (timestamps, branch, whatever the caller
-- stores), and the lifecycle operations that have to keep it in step with the
-- session it belongs to.

return function(H)
  local meta = require("sessions.meta")

  local dir, cleanup = H.fixture("meta")
  local session = dir .. "/work.vim"
  vim.fn.writefile({ "set nocompatible" }, session)

  -- Round-trip ----------------------------------------------------------------
  meta.write(session, {
    branch = "main",
    saved_at = "2026-09-19T00:00:00Z",
    cwd = dir,
    buffers = { dir .. "/a.lua", dir .. "/b.lua" },
  })
  local read = meta.read(session)
  H.ok(read, "what was written comes back")
  H.eq(read.branch, "main", "string values survive")
  H.eq(read.saved_at, "2026-09-19T00:00:00Z", "and so does the timestamp")
  H.eq(#read.buffers, 2, "and the buffer list")

  -- Validation (SEC-33 / LUA-16) -----------------------------------------------
  -- A sidecar is untrusted input -- hand-editable, or synced in from another
  -- machine/plugin version via `:Session toggle-track`. Every field is
  -- re-validated on read, and the first bad one rejects the whole thing (the
  -- same contract sessions.layout applies to its own persisted snapshot).
  -- Before this, an off-type field sailed past the `meta.field and ...`
  -- guards at the call sites -- a table is truthy -- and crashed on
  -- concatenation or ipairs() instead.
  do
    local bad = dir .. "/bad.vim"
    vim.fn.writefile({ "set nocompatible" }, bad)
    local bad_sidecar = dir .. "/.bad.json"

    -- JSON `null` decodes to a table sentinel (vim.NIL / lib.lua.null), not
    -- Lua `nil` -- and that sentinel is truthy.
    vim.fn.writefile({ '{"branch": null, "saved_at": "2026-01-01T00:00:00Z"}' }, bad_sidecar)
    H.falsy(meta.read(bad), "a null field is rejected rather than passed through as a truthy table")

    vim.fn.writefile({ '{"buffers": "not-a-list"}' }, bad_sidecar)
    H.falsy(meta.read(bad), "a wrong-shaped buffers field is rejected")

    vim.fn.writefile({ '{"saved_at": 1234}' }, bad_sidecar)
    H.falsy(meta.read(bad), "an off-type scalar field is rejected")

    vim.fn.writefile({ '{"buffers": [1, 2]}' }, bad_sidecar)
    H.falsy(meta.read(bad), "a buffers entry that is not a string is rejected")

    os.remove(bad_sidecar)
  end

  -- No sidecar ----------------------------------------------------------------
  -- A session saved before this feature existed has no sidecar, and reading one
  -- must be an ordinary "nothing there", not an error.
  H.falsy(meta.read(dir .. "/never-written.vim"), "reading a missing sidecar yields nothing")

  -- Rename --------------------------------------------------------------------
  local renamed = dir .. "/renamed.vim"
  meta.rename(session, renamed)
  H.falsy(meta.read(session), "the old name has no sidecar any more")
  local moved = meta.read(renamed)
  H.ok(moved, "the new name has one")
  H.eq(moved.branch, "main", "with the same contents")

  -- Delete --------------------------------------------------------------------
  meta.delete(renamed)
  H.falsy(meta.read(renamed), "delete removes it")

  -- Deleting one that is not there is a no-op rather than an error: `delete`
  -- runs as part of removing a session, and a session without a sidecar is a
  -- perfectly normal thing to remove.
  local ok = pcall(meta.delete, dir .. "/never-written.vim")
  H.ok(ok, "deleting a missing sidecar does not raise")

  cleanup()
end
