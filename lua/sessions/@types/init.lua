---@meta
---@module 'sessions.@types'

---@alias Sessions.Name string

---@class Sessions.Blacklist
---@field buftypes string[]
---@field filetypes string[]
---@field paths string[]

---@class Sessions.Hooks
---@field on_save? fun(name: string, path: string): nil
---@field on_load? fun(name: string, path: string): nil

---Optional normal-mode keymaps, all opt-in (`keymaps = false` by default).
---
---Covers every `:Session` subcommand that takes no *required* argument, plus
---the `:SessionLoad` picker. `delete` and `rename` are absent on purpose:
---both require a name, and a bare keypress has nothing to pass. Reach them
---through the picker or the commands themselves.
---@class Sessions.Keymaps
---@field save? string|false          `:Session save`
---@field load? string|false          `:Session load`
---@field save_ts? string|false       `:Session save-timestamp`
---@field list? string|false          `:Session list`
---@field current? string|false       `:Session current`
---@field picker? string|false        `:SessionLoad` (picker with preview)
---@field toggle_track? string|false  `:Session toggle-track`
---@field save_tab? string|false      `:Session save-tab`
---@field load_tab? string|false      `:Session load-tab`
---@field save_layout? string|false   `:Session save-layout`
---@field load_layout? string|false   `:Session load-layout`

---@class Sessions.Config
---@field root string                    Root directory for session files
---@field default_name string            Fallback session name when auto-resolve yields nothing
---@field branch_aware boolean           Suffix session name with current git branch
---@field project_aware boolean          Prefix session name with detected project root basename
---@field project_markers string[]       Filenames used to detect a project root (upward search)
---@field sessionoptions string          Passed to vim.opt.sessionoptions before each save/load
---@field relative_paths boolean         Rewrite the saved cwd to a portable placeholder, re-anchored to cwd on load
---@field root_remap table<string,string> Old-root -> new-root path prefixes translated when loading (cross-OS sync)
---@field autoload boolean|"ask"         Load the contextual session on VimEnter (no file args); "ask" prompts first
---@field autosave boolean               Autosave session on VimLeavePre
---@field autosave_name string           Fixed session name for autosave (e.g. "last")
---@field metadata boolean               Write a companion .json file with save context
---@field hooks Sessions.Hooks
---@field blacklist Sessions.Blacklist
---@field keymaps Sessions.Keymaps|false Keymaps table or false to disable all keymaps
---@field which_key { enable: boolean } Register a which-key group label for the keymap prefix

---@class Sessions.Info
---@field name string
---@field path string

---@class Sessions.StatuslineOpts
---@field icon? string        Prefix before the session name (default "")
---@field dirty_icon? string  Suffix shown when the session has unsaved layout changes (default " *")
---@field empty? string       Returned when no session is active (default "")

---@class Sessions.Meta
---@field saved_at string   ISO-8601 timestamp
---@field cwd string        Working directory at save time
---@field branch string|nil Git branch at save time
---@field buffers string[]  Buffer names included in the session

return {}
