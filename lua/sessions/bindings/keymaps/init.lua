---@module 'sessions.bindings.keymaps'
---@brief Attaches the optional, user-configured normal-mode keymaps.
---@description
--- Disabled unless `setup({ keymaps = { ... } })` supplies at least one
--- lhs; every mapping is opt-in (see docs/BINDINGS.md).
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

---@param km Sessions.Keymaps
function M.attach(km)
	if type(km) ~= "table" then
		return
	end

	local set = require("lib.nvim.map")
	local notify = require("lib.nvim.notify").create("[sessions.keymaps]")

	-- Sorted, so an "accepted" list reads the same on every run rather than in
	-- whatever order `pairs` happens to walk the table.
	local accepted = vim.tbl_keys(COMMANDS)
	table.sort(accepted)

	for name, lhs in pairs(km) do
		if lhs and lhs ~= "" then
			local spec = COMMANDS[name]
			local why = UNMAPPABLE[name]
			if why then
				notify.warn(
					("keymaps.%s is not available: %s, and a keymap has nothing to pass. "):format(name, why)
						.. "Use keymaps.picker, or the command directly."
				)
			elseif not spec then
				notify.warn(
					("Unknown keymaps.%s — ignoring. Accepted: %s"):format(
						tostring(name),
						table.concat(accepted, ", ")
					)
				)
			else
				set("n", lhs, ("<cmd>%s<cr>"):format(spec.cmd), {}, spec.desc)
			end
		end
	end
end

return M
