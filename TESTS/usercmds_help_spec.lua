-- TESTS/usercmds_help_spec.lua -- every flag of `:Session` has a line in lib.nvim's option float.
--
-- The text comes from the `desc` of each FlagSpec in sessions.bindings.usercmds (`marks add` and
-- `marks pin`). A new flag without one shows up as a bare row in the cheatsheet, so this fails until
-- it is described.

return function(H)
  local ok, composer = pcall(require, "lib.nvim.bindings.usercmd.composer")
  H.ok(ok, "the composer loads")

  -- A lib.nvim older than `help.undocumented` cannot answer the question; that is a missing
  -- feature of the dependency, not a defect of this plugin.
  if type(composer.help.undocumented) ~= "function" then
    return
  end

  require("sessions.bindings.usercmds").enable()
  H.ok(composer.registry().Session ~= nil, ":Session is registered through the composer")

  local missing = {}
  for _, m in ipairs(composer.help.undocumented("Session")) do
    missing[#missing + 1] = ("%s %s"):format(m.route, m.name)
  end
  H.eq(#missing, 0, ":Session options without a help text: " .. table.concat(missing, ", "))
end
