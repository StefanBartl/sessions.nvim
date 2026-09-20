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
---An unset field binds nothing; a field may be one lhs or a list of them,
---and `false` is the same as leaving it out.
---
---Covers every `:Session` subcommand that takes no *required* argument, plus
---the `:SessionLoad` picker. `delete` and `rename` have no entry on purpose:
---both need a name, and a bare keypress has nothing to pass — reach them
---through the picker or the commands themselves.
---@class Sessions.Keymaps
---@field save? string|string[]|false          `:Session save`
---@field load? string|string[]|false          `:Session load`
---@field save_ts? string|string[]|false       `:Session save-timestamp`
---@field list? string|string[]|false          `:Session list`
---@field current? string|string[]|false       `:Session current`
---@field picker? string|string[]|false        `:SessionLoad` (picker with preview)
---@field toggle_track? string|string[]|false  `:Session toggle-track`
---@field save_tab? string|string[]|false      `:Session save-tab`
---@field load_tab? string|string[]|false      `:Session load-tab`
---@field save_layout? string|string[]|false   `:Session save-layout`
---@field load_layout? string|string[]|false   `:Session load-layout`
---@field marks_menu? string|string[]|false      `:Session marks` (configured picker)
---@field marks_edit? string|string[]|false      `:Session marks menu edit`
---@field marks_add? string|string[]|false       `:Session marks add`
---@field marks_add_front? string|string[]|false `:Session marks add --front`
---@field marks_pin? string|string[]|false       `:Session marks pin --front`
---@field marks_remove? string|string[]|false    `:Session marks remove`
---@field marks_sync? string|string[]|false      `:Session marks defaults sync`
---@field marks_debug? string|string[]|false     `:Session marks debug`

---@class Sessions.Marks.Menu
---@field ui "auto"|"edit"|"kit"|"snacks"|"telescope"|"fzf"
---@field pin_marker string

---@class Sessions.Marks.Preview
---@field max_kb integer
---@field max_lines integer

---@class Sessions.Marks.Config
---@field enable boolean
---@field scope "global"|"project"
---@field defaults (string|string[])[]   Path specs seeded on first use; segments may start with `$REPOS_DIR`, `$HOME`, `$NVIM_HOME`
---@field import_harpoon boolean         First run: take over harpoon's single-global-list bucket when one exists
---@field context_debounce_ms integer
---@field menu Sessions.Marks.Menu
---@field preview Sessions.Marks.Preview
---@field select_key string|false        Template with `%d`, bound for 1..9
---@field preview_key string|false       Template with `%d`, bound for 1..9

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
---@field autosave_name string|boolean   Autosave target: `true` = branch/project-aware auto-resolve (like a bare `:Session save`); a string pins autosave to that fixed name regardless of project; `false` disables autosave despite `autosave = true`
---@field metadata boolean               Write a companion .json file with save context
---@field restore_buffer_order boolean   Persist/restore per-tabpage `vim.t.bufs` order (NvChad tabufline etc.); no-op without such a tabline
---@field hooks Sessions.Hooks
---@field blacklist Sessions.Blacklist
---@field keymaps Sessions.Keymaps|false Keymaps table or false to disable all keymaps
---@field which_key { enable: boolean } Register a which-key group label for the keymap prefix
---@field marks Sessions.Marks.Config    The mark list (`:Session marks`); off by default

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

--- What `setup()` accepts: the shape of `Sessions.Config` with every field
--- optional, nested tables included. The resolved `Sessions.Config` stays
--- strict for everything after the merge.
---@class Sessions.Opts
---@field root?            string                    Root directory for session files
---@field default_name?    string            Fallback session name when auto-resolve yields nothing
---@field branch_aware?    boolean           Suffix session name with current git branch
---@field project_aware?   boolean          Prefix session name with detected project root basename
---@field project_markers? string[]       Filenames used to detect a project root (upward search)
---@field sessionoptions?  string          Passed to vim.opt.sessionoptions before each save/load
---@field relative_paths?  boolean         Rewrite the saved cwd to a portable placeholder, re-anchored to cwd on load
---@field root_remap?      table<string,string> Old-root -> new-root path prefixes translated when loading (cross-OS sync)
---@field autoload?        boolean|"ask"         Load the contextual session on VimEnter (no file args); "ask" prompts first
---@field autosave?        boolean               Autosave session on VimLeavePre
---@field autosave_name?   string|boolean   Autosave target: `true` = branch/project-aware auto-resolve (like a bare `:Session save`); a string pins autosave to that fixed name regardless of project; `false` disables autosave despite `autosave = true`
---@field metadata?        boolean               Write a companion .json file with save context
---@field restore_buffer_order? boolean          Persist/restore per-tabpage `vim.t.bufs` order (NvChad tabufline etc.); no-op without such a tabline
---@field hooks?           Sessions.Hooks.Opts
---@field blacklist?       Sessions.Blacklist.Opts
---@field keymaps?         Sessions.Keymaps.Opts|false Keymaps table or false to disable all keymaps
---@field which_key?       { enable: boolean } Register a which-key group label for the keymap prefix
---@field marks?           Sessions.Marks.Opts       The mark list (`:Session marks`); off by default

---@class Sessions.Blacklist.Opts
---@field buftypes?  string[]
---@field filetypes? string[]
---@field paths?     string[]

---@class Sessions.Hooks.Opts
---@field on_save? fun(name: string, path: string): nil
---@field on_load? fun(name: string, path: string): nil

---@class Sessions.Keymaps.Opts
---@field save?         string|string[]|false          `:Session save`
---@field load?         string|string[]|false          `:Session load`
---@field save_ts?      string|string[]|false       `:Session save-timestamp`
---@field list?         string|string[]|false          `:Session list`
---@field current?      string|string[]|false       `:Session current`
---@field picker?       string|string[]|false        `:SessionLoad` (picker with preview)
---@field toggle_track? string|string[]|false  `:Session toggle-track`
---@field save_tab?     string|string[]|false      `:Session save-tab`
---@field load_tab?     string|string[]|false      `:Session load-tab`
---@field save_layout?  string|string[]|false   `:Session save-layout`
---@field load_layout?  string|string[]|false   `:Session load-layout`
---@field marks_menu?      string|string[]|false `:Session marks`
---@field marks_edit?      string|string[]|false `:Session marks menu edit`
---@field marks_add?       string|string[]|false `:Session marks add`
---@field marks_add_front? string|string[]|false `:Session marks add --front`
---@field marks_pin?       string|string[]|false `:Session marks pin --front`
---@field marks_remove?    string|string[]|false `:Session marks remove`
---@field marks_sync?      string|string[]|false `:Session marks defaults sync`
---@field marks_debug?     string|string[]|false `:Session marks debug`

---@class Sessions.Marks.Opts
---@field enable?              boolean
---@field scope?               "global"|"project"
---@field defaults?            (string|string[])[]
---@field import_harpoon?      boolean
---@field context_debounce_ms? integer
---@field menu?                { ui?: "auto"|"edit"|"kit"|"snacks"|"telescope"|"fzf", pin_marker?: string }
---@field preview?             { max_kb?: integer, max_lines?: integer }
---@field select_key?          string|false
---@field preview_key?         string|false
return {}
