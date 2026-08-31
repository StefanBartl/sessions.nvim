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
  meta.write(session, { branch = "main", saved_at = 1234 })
  local read = meta.read(session)
  H.ok(read, "what was written comes back")
  H.eq(read.branch, "main", "string values survive")
  H.eq(read.saved_at, 1234, "and numbers stay numbers rather than becoming strings")

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
