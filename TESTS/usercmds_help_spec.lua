-- TESTS/usercmds_help_spec.lua -- every flag and positional argument of `:Session` has a line in
-- lib.nvim's option float.
--
-- The text comes from the `desc` of each FlagSpec / ArgSpec in sessions.bindings.usercmds, or from
-- the text of an argument's type (`register_type`: SESSION, TAB_SESSION, LAYOUT, MARKS_MENU). A new
-- flag or argument without one shows up as a bare row in the cheatsheet, so this fails until it is
-- described.

return function(H)
  local ok, composer = pcall(require, "lib.nvim.bindings.usercmd.composer")
  H.ok(ok, "the composer loads")

  -- A lib.nvim older than `help.undocumented` cannot answer the question; that is a missing
  -- feature of the dependency, not a defect of this plugin.
  if type(composer.help.undocumented) ~= "function" then
    return
  end
  local entries = require("lib.nvim.bindings.usercmd.composer.help.entries")

  require("sessions.bindings.usercmds").enable()
  H.ok(composer.registry().Session ~= nil, ":Session is registered through the composer")

  local missing = {}
  -- `args = true` also lists the positional arguments (an older lib.nvim ignores it).
  for _, m in ipairs(composer.help.undocumented("Session", { args = true })) do
    missing[#missing + 1] = ("%s %s %s"):format(m.route, m.kind, m.name)
  end
  H.eq(
    #missing,
    0,
    ":Session options and arguments without a help text: " .. table.concat(missing, ", ")
  )

  -- The house style of the float: one short line, no trailing full stop.
  local walked = 0
  for _, route in ipairs(composer.registry().Session:spec().routes or {}) do
    local path = table.concat(route.path, " ")
    for _, arg in ipairs(route.args or {}) do
      local text = entries.arg_desc and entries.arg_desc(arg) or arg.desc
      if text then
        walked = walked + 1
        local label = (":Session %s %s"):format(path, arg.name)
        H.ok(not text:find("\n", 1, true), label .. " is one line")
        H.ok(#text <= 80, label .. " stays short (" .. #text .. " chars)")
        H.ok(not text:find("%.$"), label .. " has no trailing full stop")
      end
    end
  end
  H.ok(walked > 0, "the routes' argument texts were actually walked")
end
