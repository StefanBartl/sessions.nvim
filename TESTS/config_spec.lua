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

  -- --------------------------------------------- DEFAULTS stays pure data (LUA-06)

  -- A bare `require` must not compute anything env-/FS-dependent: the
  -- platform-specific blacklist is resolved by config/init.lua's setup()
  -- instead, right after DEFAULTS is required.
  H.eq(#DEFAULTS.blacklist.paths, 0, "DEFAULTS.blacklist.paths is empty at require time")

  -- ...but setup() still fills it in, for the common case of not overriding it.
  config.setup({})
  H.ok(#config.get().blacklist.paths > 0, "setup() resolves the platform default")

  -- An explicit override is never clobbered by that resolution.
  config.setup({ blacklist = { paths = { "/only/mine/" } } })
  H.eq(
    config.get().blacklist.paths[1],
    "/only/mine/",
    "an explicit blacklist.paths wins over the platform default"
  )
  config.setup({})

  -- --------------------------------------------- setup() validation (ERR-50/ERR-22)

  -- An unknown key is dropped (not silently merged in, and not left to crash
  -- a module downstream) and reported with a did-you-mean hint.
  config.setup({ defalt_name = "typo" })
  H.eq(config.get().default_name, default_name, "an unknown key never reaches cfg")
  local issues = config.issues()
  H.eq(#issues, 1, "and is recorded as one issue")
  H.contains(issues[1], "defalt_name", "naming the bad key")
  H.contains(issues[1], "default_name", "with a did-you-mean hint")

  -- A value of the wrong shape is dropped so the default takes effect,
  -- instead of crashing whatever reads it as the documented type.
  ---@diagnostic disable-next-line: assign-type-mismatch
  config.setup({ project_markers = "not-a-list" })
  H.eq(
    table.concat(config.get().project_markers, ","),
    table.concat(DEFAULTS.project_markers, ","),
    "a wrong-shaped list value falls back to the default"
  )
  H.eq(#config.issues(), 1, "and is recorded as one issue")
  H.contains(config.issues()[1], "project_markers", "naming the bad key")

  -- An unknown key nested one level deep is caught too.
  ---@diagnostic disable-next-line: missing-fields
  config.setup({ blacklist = { pathz = { "/x" } } })
  H.eq(#config.issues(), 1, "a nested unknown key is recorded")
  H.contains(config.issues()[1], "blacklist.pathz", "qualified with its parent key")

  -- ...and so is one nested two levels deep (`marks.menu.*`, `marks.preview.*`)
  -- -- validate() recurses to whatever depth Sessions.Config itself nests,
  -- not just into the top-level tables.
  ---@diagnostic disable-next-line: missing-fields
  config.setup({ marks = { menu = { uii = "edit" } } })
  H.eq(#config.issues(), 1, "a doubly-nested unknown key is recorded")
  H.contains(config.issues()[1], "marks.menu.uii", "qualified with its full dotted path")
  H.contains(config.issues()[1], "marks.menu.ui", "with a did-you-mean hint")
  H.eq(
    config.get().marks.menu.ui,
    DEFAULTS.marks.menu.ui,
    "the rest of marks.menu falls back to the default, not just vanishes"
  )

  -- A recognized doubly-nested key still reaches cfg unmangled.
  config.setup({ marks = { preview = { max_kb = 42 } } })
  H.eq(#config.issues(), 0, "a well-formed doubly-nested key raises no issue")
  H.eq(config.get().marks.preview.max_kb, 42, "and survives into cfg")
  H.eq(
    config.get().marks.preview.max_lines,
    DEFAULTS.marks.preview.max_lines,
    "a sibling the user did not set keeps its default"
  )

  config.setup({})

  -- A clean setup() reports nothing.
  config.setup({ default_name = "custom" })
  H.eq(#config.issues(), 0, "a fully recognized, well-typed opts table raises no issue")

  -- `keymaps.delete`/`keymaps.rename` are real subcommands that are
  -- deliberately unmappable (see docs/BINDINGS.md) -- sessions.bindings.
  -- keymaps has its own UNMAPPABLE table that explains why and refuses to
  -- bind them. validate() must recognize both names and let them through
  -- unchanged, not treat them as typos and strip them before that dedicated
  -- explanation ever gets a chance to run.
  config.setup({ keymaps = { delete = "gQd", rename = "gQr", save = "gQs" } })
  H.eq(#config.issues(), 0, "keymaps.delete/rename are not reported as unknown")
  H.eq(config.get().keymaps.delete, "gQd", "and keymaps.delete survives into cfg")
  H.eq(config.get().keymaps.rename, "gQr", "as does keymaps.rename")
  H.eq(config.get().keymaps.save, "gQs", "alongside an ordinary mappable name")

  config.setup({})

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
      -- `\\f.txt`, a literal backslash: `"\f.txt"` (without the doubled
      -- backslash) is Lua's own escape for a form-feed byte, not "\f" as
      -- text -- a typo that happened to still pass, since the blacklist also
      -- carries the bare, separator-less spelling of $TEMP as one of its
      -- candidates (see config/init.lua), which prefix-matches this string
      -- regardless of what character follows it.
      H.ok(blacklisted(temp .. "\\f.txt"), "blacklist: $TEMP as spelled, backslashes")

      local real = uv.fs_realpath(temp)
      if real and real ~= temp then
        local long = (real:gsub("\\", "/"))
        H.ok(blacklisted(long .. "/f.txt"), "blacklist: the resolved $TEMP, forward slashes")
        H.ok(blacklisted(real .. "\\f.txt"), "blacklist: the resolved $TEMP, backslashes")
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
