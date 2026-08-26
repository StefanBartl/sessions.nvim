---@module 'sessions.bindings.keymaps'
---@brief Attaches the optional, user-configured normal-mode keymaps.
---@description
--- Disabled unless `setup({ keymaps = { ... } })` supplies at least one
--- lhs; every mapping is opt-in (see docs/BINDINGS.md). An lhs may be one
--- key or a list of them.
---
--- Every `:Session` subcommand that takes no *required* argument is
--- available here, plus the `:SessionLoad` picker. That qualifier is the
--- whole rule: a keymap is a bare keypress with nothing to pass, so
--- `:Session delete <name>` and `:Session rename <old> <new>` cannot be
--- mapped meaningfully and deliberately have no entry. It is not that they
--- are destructive -- `:Session save` overwrites just as happily and is
--- mapped -- it is that there is no argument to supply. Use `:SessionLoad`'s
--- picker, or the commands directly, for those two.

---@class SessionsBindingsKeymaps
local M = {}

---Every keymap name, and the command it runs.
---
--- `save`/`load`/`save_ts`/`list` keep their historical names even though
--- `save_ts` does not match its subcommand (`save-timestamp`): renaming them
--- would silently break existing configs.
---@internal
---@type table<string, { cmd: string, desc: string }>
local COMMANDS = {
  save = { cmd = "Session save", desc = "Session: save" },
  load = { cmd = "Session load", desc = "Session: load" },
  save_ts = { cmd = "Session save-timestamp", desc = "Session: save with timestamp" },
  list = { cmd = "Session list", desc = "Session: list" },
  current = { cmd = "Session current", desc = "Session: show active session" },
  picker = { cmd = "SessionLoad", desc = "Session: pick a session (preview)" },
  toggle_track = { cmd = "Session toggle-track", desc = "Session: toggle git skip-worktree" },
  save_tab = { cmd = "Session save-tab", desc = "Session: save this tab's layout" },
  load_tab = { cmd = "Session load-tab", desc = "Session: load a tab layout" },
  save_layout = { cmd = "Session save-layout", desc = "Session: save window layout" },
  load_layout = { cmd = "Session load-layout", desc = "Session: load window layout" },
}

---Subcommands that exist but cannot be a keymap, and why.
---
--- Worth distinguishing from a typo: someone setting `keymaps.delete` has
--- guessed a real subcommand, and "Unknown keymaps.delete" would send them
--- looking for a spelling mistake that isn't there.
---@internal
---@type table<string, string>
local UNMAPPABLE = {
  delete = ":Session delete requires a name",
  rename = ":Session rename requires an old and a new name",
}

---@internal
--- The longest prefix every configured lhs starts with, or nil.
---
--- Computed rather than fixed: these keymaps are entirely opt-in, so the
--- plugin does not know where the user put them. Labelling `<leader>s` when
--- they chose `<leader>q` would name somebody else's prefix, and labelling
--- nothing at all when they did pick a shared one loses the group.
---@param bound Lib.Keymap.Registered[]
---@return string|nil
local function common_prefix(bound)
  ---@type string[]
  local lhs_list = {}
  for _, e in ipairs(bound) do
    if e.lhs and e.bound then
      lhs_list[#lhs_list + 1] = e.lhs
    end
  end
  if #lhs_list == 0 then
    return nil
  end

  local prefix = lhs_list[1]:sub(1, -2)
  for _, lhs in ipairs(lhs_list) do
    while prefix ~= "" and lhs:sub(1, #prefix) ~= prefix do
      prefix = prefix:sub(1, -2)
    end
  end
  return prefix ~= "" and prefix or nil
end

---Declare the keymap actions and bind whichever ones the user configured.
---
---Declared through `lib.nvim.bindings.keymap`'s registry: the actions exist
---whether or not they are bound, which is what lets `:checkhealth` and the
---generated docs answer "what can be mapped" rather than only "what is
---mapped". An override may now also be a *list* of keys.
---@param km Sessions.Keymaps
---@param which_key? boolean  # `false` skips the group label only.
---@return Lib.Keymap.Registered[]
function M.attach(km, which_key)
  if type(km) ~= "table" then
    return {}
  end

  local notify = require("lib.nvim.notify").create("[sessions.keymaps]")

  -- Worth catching before the registry does: someone setting `keymaps.delete`
  -- has guessed a real subcommand, and the registry's "no such keymap action"
  -- would send them looking for a spelling mistake that isn't there.
  ---@type Sessions.Keymaps
  local user = {}
  for name, lhs in pairs(km) do
    local why = UNMAPPABLE[name]
    if why then
      notify.warn(
        ("keymaps.%s is not available: %s, and a keymap has nothing to pass. "):format(name, why)
          .. "Use keymaps.picker, or the command directly."
      )
    else
      user[name] = lhs
    end
  end

  ---@type table<string, Lib.Keymap.Action>
  local actions = {}
  ---@type string[]
  local order = vim.tbl_keys(COMMANDS)
  -- Sorted, so the docs and the health report read the same on every run
  -- rather than in whatever order `pairs` happened to walk the table.
  table.sort(order)
  for _, name in ipairs(order) do
    local entry = COMMANDS[name]
    actions[name] = {
      -- No `default`: every one of these is opt-in, and always has been.
      rhs = ("<cmd>%s<cr>"):format(entry.cmd),
      -- The registry prefixes the plugin name itself.
      desc = entry.desc:gsub("^Session: ", ""),
    }
  end

  local bound = require("lib.nvim.bindings.keymap").register(
    "Session",
    { order = order, actions = actions },
    user
  )

  local prefix = which_key ~= false and common_prefix(bound) or nil
  if prefix then
    require("lib.nvim.bindings.keymap.which_key").add_group({
      prefix = prefix,
      group = "Session",
    })
  end

  return bound
end

return M
