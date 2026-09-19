---@module 'sessions.bindings.keymaps'
---@brief Attaches the optional, user-configured normal-mode keymaps.
---@description
--- Disabled unless `setup({ keymaps = { ... } })` supplies at least one
--- lhs; every mapping is opt-in (see docs/BINDINGS.md). An lhs may be one
--- key or a list of them.
---
--- Every `:Session` subcommand that takes no *required* argument is
--- mappable, plus the `:SessionLoad` picker. `delete`/`rename` are not: a
--- keymap has no argument to pass (not a destructiveness call — `save`
--- overwrites too and is mapped). Use the picker or the commands directly.

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

---The mark-list actions, declared only while `marks.enable` is on so a host
---without the feature is not shown keys that would only say "marks are off".
---@internal
---@type table<string, { cmd: string, desc: string }>
local MARKS_COMMANDS = {
  marks_menu = { cmd = "Session marks", desc = "Session: marks (picker)" },
  marks_edit = { cmd = "Session marks menu edit", desc = "Session: marks (edit list)" },
  marks_add = { cmd = "Session marks add", desc = "Session: mark this file" },
  marks_add_front = { cmd = "Session marks add --front", desc = "Session: mark this file first" },
  marks_pin = { cmd = "Session marks pin --front", desc = "Session: pin this file" },
  marks_remove = { cmd = "Session marks remove", desc = "Session: unmark this file" },
  marks_sync = { cmd = "Session marks defaults sync", desc = "Session: add missing default marks" },
  marks_debug = { cmd = "Session marks debug", desc = "Session: dump the mark list" },
}

---Subcommands that exist but cannot be a keymap, and why. Kept distinct from
---an unknown-name error: `keymaps.delete` is a real subcommand, so "no such
---keymap" would send the user hunting a typo that isn't there.
---@internal
---@type table<string, string>
local UNMAPPABLE = {
  delete = ":Session delete requires a name",
  rename = ":Session rename requires an old and a new name",
}

---@internal
---Resolve a notifier; graceful fallback if lib.nvim's notify is absent,
---matching the convention used in bindings/usercmds and marks (lib.nvim.notify
---is soft-guarded per docs/installation.md -- unlike lib.nvim.bindings.keymap
---just below, which has no such fallback and is documented separately).
---@return table
local function notifier()
  local ok, lib = pcall(require, "lib.nvim.notify")
  if ok then
    return lib.create("[sessions.keymaps]")
  end
  return {
    info = function(msg)
      vim.notify("[sessions.keymaps] " .. msg, vim.log.levels.INFO)
    end,
    warn = function(msg)
      vim.notify("[sessions.keymaps] " .. msg, vim.log.levels.WARN)
    end,
    error = function(msg)
      vim.notify("[sessions.keymaps] " .. msg, vim.log.levels.ERROR)
    end,
  }
end

---@internal
---Whether the mark list is on, read from the live config. The `km` argument
---is only there so the check reads at its call site as being about the
---user's keymap table; the decision is the config's.
---@param _ table
---@return boolean
local function marks_on_for(_)
  local cfg = require("sessions.config").get().marks
  return type(cfg) == "table" and cfg.enable == true
end

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

  local notify = notifier()

  -- Filter UNMAPPABLE names out before the registry sees them, so the user
  -- gets the "needs a name" reason rather than a bare "no such keymap action".
  ---@type Sessions.Keymaps
  local user = {}
  for name, lhs in pairs(km) do
    local why = UNMAPPABLE[name]
    if not why and MARKS_COMMANDS[name] and not marks_on_for(km) then
      why = "marks are off (marks.enable = false)"
    end
    if why then
      notify.warn(
        ("keymaps.%s is not available: %s, and a keymap has nothing to pass. "):format(name, why)
          .. "Use keymaps.picker, or the command directly."
      )
    else
      user[name] = lhs
    end
  end

  local marks_cfg = require("sessions.config").get().marks
  local marks_on = type(marks_cfg) == "table" and marks_cfg.enable == true

  ---@type table<string, { cmd: string, desc: string }>
  local commands = vim.deepcopy(COMMANDS)
  if marks_on then
    for name, entry in pairs(MARKS_COMMANDS) do
      commands[name] = entry
    end
  end

  ---@type table<string, Lib.Keymap.Action>
  local actions = {}
  ---@type string[]
  local order = vim.tbl_keys(commands)
  -- Sorted, so the docs and the health report read the same on every run
  -- rather than in whatever order `pairs` happened to walk the table.
  table.sort(order)
  for _, name in ipairs(order) do
    local entry = commands[name]
    actions[name] = {
      -- No `default`: every one of these is opt-in, and always has been.
      rhs = ("<cmd>%s<cr>"):format(entry.cmd),
      -- The registry prefixes the plugin name itself.
      desc = entry.desc:gsub("^Session: ", ""),
    }
  end

  -- The numbered jumps: `marks.select_key`/`preview_key` are templates with
  -- one `%d`, expanded for 1..9. Declared with a `default` -- the template
  -- IS the configuration -- so they bind without a `keymaps` entry each.
  if marks_on then
    for _, spec in ipairs({
      {
        key = "select_key",
        name = "marks_select_%d",
        cmd = "Session marks select %d",
        desc = "jump to mark %d",
      },
      {
        key = "preview_key",
        name = "marks_preview_%d",
        cmd = "Session marks preview %d",
        desc = "preview mark %d",
      },
    }) do
      local template = marks_cfg[spec.key]
      if type(template) == "string" and template:find("%%d") then
        for i = 1, 9 do
          local name = spec.name:format(i)
          order[#order + 1] = name
          actions[name] = {
            default = template:format(i),
            rhs = ("<cmd>%s<cr>"):format(spec.cmd:format(i)),
            desc = spec.desc:format(i),
          }
        end
      end
    end
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
