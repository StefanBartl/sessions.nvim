-- TESTS/config_spec.lua — sessions.config: the merge, that DEFAULTS is not
-- mutated by it, and that the Windows %TEMP% blacklist covers every spelling
-- of that directory the OS can hand back.

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

  -- ------------------------------------------------- the %TEMP% blacklist

  -- The blacklist is a plain prefix compare, so it only works on the exact
  -- spelling a buffer name carries. On Windows there are two: $TEMP is the
  -- 8.3 short form (`C:/Users/STEFAN~1/...`) for any profile name over eight
  -- characters, while anything opened through a resolved path -- fs_realpath,
  -- an LSP, a picker -- carries the long one. Registering only the short form
  -- let every long-spelled temp buffer into the session file.
  if vim.fn.has("win32") == 1 then
    local uv = vim.uv or vim.loop
    local temp = vim.fn.expand("$TEMP")

    if temp and temp ~= "" and temp ~= "$TEMP" then
      local paths = config.get().blacklist.paths

      ---@param s string
      ---@return boolean
      local function blacklisted(s)
        for i = 1, #paths do
          local pref = paths[i]
          if pref and s:sub(1, #pref) == pref then
            return true
          end
        end
        return false
      end

      local short = (temp:gsub("\\", "/"))
      H.ok(blacklisted(short .. "/f.txt"), "blacklist: $TEMP as spelled, forward slashes")
      H.ok(blacklisted(temp .. "\f.txt"), "blacklist: $TEMP as spelled, backslashes")

      local real = uv.fs_realpath(temp)
      if real and real ~= temp then
        local long = (real:gsub("\\", "/"))
        H.ok(blacklisted(long .. "/f.txt"), "blacklist: the resolved $TEMP, forward slashes")
        H.ok(blacklisted(real .. "\f.txt"), "blacklist: the resolved $TEMP, backslashes")
      end

      -- No entry may mix the two separators: a buffer name never does, so such
      -- a prefix can only ever match nothing.
      for i = 1, #paths do
        local pref = paths[i]
        local mixed = pref:find("/", 1, true) and pref:find("\\", 1, true)
        H.ok(not mixed, "blacklist: no mixed-separator prefix (" .. pref .. ")")
      end
    end
  end
end
