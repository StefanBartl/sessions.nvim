-- TESTS/keymaps_spec.lua — sessions.bindings.keymaps: the opt-in normal-mode
-- mappings.
--
-- Every mapping here is opt-in, which makes "what is declared" and "what is
-- bound" two different questions -- `:checkhealth` and the generated docs
-- answer the first, the user's own config decides the second. Both are
-- asserted against lib.nvim's real keymap registry and against Neovim's real
-- mapping table; nothing about this needs a stub.

return function(H)
  local keymaps = require("sessions.bindings.keymaps")

  ---Is `lhs` mapped in normal mode right now?
  ---@param lhs string
  ---@return boolean
  local function mapped(lhs)
    return vim.fn.maparg(lhs, "n") ~= ""
  end

  ---@param bound table[]
  ---@param name string
  ---@return table|nil
  local function entry(bound, name)
    for _, e in ipairs(bound) do
      if e.name == name then
        return e
      end
    end
    return nil
  end

  -- Not a table -> nothing happens ---------------------------------------------
  -- `keymaps = false` is the default, and `setup()` passes `cfg.keymaps or {}`
  -- -- but M.attach is public, so a stray value must not raise.
  ---@diagnostic disable-next-line: param-type-mismatch
  H.eq(#keymaps.attach(false), 0, "a non-table configuration binds nothing")
  ---@diagnostic disable-next-line: param-type-mismatch
  H.eq(#keymaps.attach("nope"), 0, "and neither does a string")

  -- Nothing configured ---------------------------------------------------------
  local none = keymaps.attach({}, false)
  H.ok(#none > 0, "the actions are declared even when none is configured")
  local save = entry(none, "save")
  H.ok(save, "`save` is one of them")
  ---@cast save -nil
  H.falsy(save.bound, "but it is not bound")
  H.contains(save.rhs, "Session save", "and it runs the matching subcommand")

  -- Every declared name maps onto a real `:Session` subcommand (or the picker
  -- command): a typo here would register a keymap that errors when pressed.
  for _, e in ipairs(none) do
    local cmd = e.rhs:match("^<cmd>(.-)<cr>$")
    H.ok(cmd, ("%s runs a command"):format(e.name))
  end

  -- Binding --------------------------------------------------------------------
  local bound = keymaps.attach({
    save = "gQs",
    load = { "gQl", "gQL" },
  }, false)

  local save_b = entry(bound, "save")
  ---@cast save_b -nil
  H.ok(save_b.bound, "a configured action is bound")
  H.ok(mapped("gQs"), "and the key really is mapped in Neovim")
  H.ok(mapped("gQl"), "a list of keys binds each of them")
  H.ok(mapped("gQL"), "including the second one")
  H.falsy(mapped("gQx"), "and nothing else")

  H.contains(
    vim.fn.maparg("gQs", "n"),
    "Session save",
    "the mapping runs the subcommand it was declared with"
  )

  -- Unmappable names ------------------------------------------------------------
  -- `delete`/`rename` are real subcommands that need an argument, so they are
  -- refused with that reason rather than with "no such keymap action" -- which
  -- would send the user hunting for a typo that is not there.
  local warned = {}
  local restore_notify = H.stub("lib.nvim.notify", {
    create = function()
      return {
        warn = function(msg)
          warned[#warned + 1] = msg
        end,
        info = function() end,
        error = function() end,
      }
    end,
  })

  local with_unmappable = keymaps.attach({ delete = "gQd", rename = "gQr" }, false)
  H.eq(#warned, 2, "each unmappable name is reported")
  H.contains(table.concat(warned, "\n"), "requires a name", "with the reason it cannot be mapped")
  H.contains(table.concat(warned, "\n"), "Use keymaps.picker", "and what to do instead")
  H.falsy(mapped("gQd"), "and nothing is bound for it")
  H.falsy(entry(with_unmappable, "delete"), "nor does it reach the registry")

  restore_notify()

  -- which-key group -------------------------------------------------------------
  -- The group label is computed from the keys the user actually chose: these
  -- keymaps are entirely opt-in, so labelling a prefix the plugin picked would
  -- name somebody else's keys.
  local added = {}
  local restore_wk = H.stub("lib.nvim.bindings.keymap.which_key", {
    add_group = function(opts)
      added[#added + 1] = opts
    end,
  })

  keymaps.attach({ save = "gWs", load = "gWl", list = "gWi" }, true)
  H.eq(#added, 1, "one group is registered")
  H.eq(added[1].prefix, "gW", "under the prefix the configured keys share")
  H.eq(added[1].group, "Session", "labelled with the plugin's name")

  -- No shared prefix -> no group: there is nothing honest to label.
  added = {}
  keymaps.attach({ save = "gZs", load = "<F12>" }, true)
  H.eq(#added, 0, "unrelated keys get no group label")

  -- which_key = false skips the label even when there is a common prefix.
  added = {}
  keymaps.attach({ save = "gYs", load = "gYl" }, false)
  H.eq(#added, 0, "which_key = false suppresses the group")

  restore_wk()

  -- Clean up every mapping this spec made.
  for _, lhs in ipairs({
    "gQs",
    "gQl",
    "gQL",
    "gWs",
    "gWl",
    "gWi",
    "gZs",
    "<F12>",
    "gYs",
    "gYl",
  }) do
    pcall(vim.keymap.del, "n", lhs)
  end
  H.falsy(mapped("gQs"), "the spec leaves no mappings behind")
end
