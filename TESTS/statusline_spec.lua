-- TESTS/statusline_spec.lua — sessions.statusline.component: the string a
-- statusline plugin renders. Called on every redraw, so what it does when
-- there is no session is as important as what it does when there is.

return function(H)
  local statusline = require("sessions.statusline")
  local core = require("sessions.core")

  -- No session ---------------------------------------------------------------
  H.eq(core.current(), nil, "no session is loaded in a headless run")
  H.eq(statusline.component(), "", "and the component renders as nothing at all")
  H.eq(
    statusline.component({ empty = "no session" }),
    "no session",
    "unless the caller asked for a placeholder"
  )

  -- The options are the caller's, per call --------------------------------------
  -- lualine and heirline both pass the same table on every redraw, so the
  -- component must not mutate it -- a caller that got its own table changed
  -- underneath would see its configuration drift over a session.
  local opts = { icon = "S ", empty = "-" }
  local before = vim.deepcopy(opts)
  statusline.component(opts)
  statusline.component(opts)
  H.eq(vim.inspect(opts), vim.inspect(before), "the caller's options table is not modified")

  -- The same table twice must come back identically: the merged options are
  -- memoized per caller table, and a cache that answered differently on the
  -- second redraw would make the statusline flicker.
  H.eq(statusline.component(opts), statusline.component(opts), "repeated calls agree")

  -- With a session ------------------------------------------------------------
  -- A real one, saved into a fixture root: `component()` reads core's state,
  -- and what it renders is only meaningful against the real thing.
  local config = require("sessions.config")
  local dir, cleanup = H.fixture("statusline")
  config.setup({
    root = dir,
    branch_aware = false,
    project_aware = false,
    metadata = false,
    restore_buffer_order = false,
  })

  H.ok(core.save("work"), "a session is saved")
  H.eq(statusline.component(), "work", "the component renders the session name")
  H.eq(statusline.component({ icon = "S " }), "S work", "behind the configured icon")

  -- The dirty marker tracks structural changes (a window or a buffer added or
  -- removed) -- what the next autosave would capture -- rather than whether
  -- some buffer has unsaved text.
  H.falsy(core.dirty(), "a freshly saved session is clean")
  core.mark_dirty()
  H.eq(statusline.component(), "work *", "a dirty session gets the default marker")
  H.eq(
    statusline.component({ dirty_icon = " [+]" }),
    "work [+]",
    "or whatever marker the caller configured"
  )
  H.eq(statusline.component({ dirty_icon = "" }), "work", "and none at all if it wants none")

  core.save("work")
  H.eq(statusline.component(), "work", "saving clears the marker again")

  -- Leave no session behind: every later spec assumes a headless run has none.
  core.delete("work")
  H.falsy(core.current(), "no session is active again")
  H.eq(statusline.component(), "", "and the component is back to nothing")

  config.setup({})
  cleanup()
end
