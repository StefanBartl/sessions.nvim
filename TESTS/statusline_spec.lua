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
end
