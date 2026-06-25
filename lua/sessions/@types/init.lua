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

---@class Sessions.Keymaps
---@field save? string|false
---@field load? string|false
---@field save_ts? string|false
---@field list? string|false

---@class Sessions.Config
---@field root string                    Root directory for session files
---@field default_name string            Fallback session name when auto-resolve yields nothing
---@field branch_aware boolean           Suffix session name with current git branch
---@field project_aware boolean          Prefix session name with detected project root basename
---@field project_markers string[]       Filenames used to detect a project root (upward search)
---@field sessionoptions string          Passed to vim.opt.sessionoptions before each save/load
---@field autoload boolean               Load the contextual session on VimEnter (no file args)
---@field autosave boolean               Save the contextual session on VimLeavePre
---@field metadata boolean               Write a companion .json file with save context
---@field hooks Sessions.Hooks
---@field blacklist Sessions.Blacklist
---@field keymaps Sessions.Keymaps|false Keymaps table or false to disable all keymaps

---@class Sessions.Info
---@field name string
---@field path string

---@class Sessions.Meta
---@field saved_at string   ISO-8601 timestamp
---@field cwd string        Working directory at save time
---@field branch string|nil Git branch at save time
---@field buffers string[]  Buffer names included in the session

return {}
