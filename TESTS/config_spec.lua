-- TESTS/config_spec.lua — sessions.config: the merge, and that DEFAULTS is not
-- mutated by it.

return function(H)
  local config = require("sessions.config")
  local DEFAULTS = require("sessions.config.DEFAULTS")

  local default_name = DEFAULTS.default_name

  local fresh = config.get()
  H.eq(fresh.default_name, default_name, "get() before setup() returns the defaults")
  H.ok(fresh ~= DEFAULTS, "as a copy, not the DEFAULTS table itself")

  config.setup({ default_name = "custom" })
  H.eq(config.get().default_name, "custom", "a user value wins")
  H.eq(
    config.get().project_aware,
    DEFAULTS.project_aware,
    "a key the user did not set keeps its default"
  )
  H.eq(DEFAULTS.default_name, default_name, "DEFAULTS itself was not mutated")

  config.setup({})
  H.eq(config.get().default_name, default_name, "setup({}) restores the defaults")
end
