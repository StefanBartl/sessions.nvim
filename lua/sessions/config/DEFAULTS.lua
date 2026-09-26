---@module 'sessions.config.DEFAULTS'
--- Default `Sessions.Config` values, merged with user opts in
--- `sessions.config`'s `setup()`.
---
--- Pure data only: a bare `require("sessions.config.DEFAULTS")` must stay
--- side-effect-free (docgen, tests and any early accessor-less reference
--- depend on that), so nothing here reads the environment or the
--- filesystem. `blacklist.paths` below is deliberately empty for the same
--- reason -- the platform-specific default is resolved by
--- `sessions.config`'s `M.setup()` instead, right after DEFAULTS is
--- required, the same place that already re-checks the runtime %TEMP% value
--- (see config/init.lua's `default_blacklist_paths()`).

---@type Sessions.Config
return {
  root = vim.fn.stdpath("data") .. "/sessions",
  default_name = "last",
  branch_aware = true,
  project_aware = true,
  project_markers = { ".git", "pyproject.toml", "package.json", "Makefile", "Cargo.toml", "go.mod" },
  sessionoptions = "buffers,curdir,tabpages,winsize,help,folds",
  relative_paths = false,
  root_remap = {},
  autoload = false,
  autosave = true,
  -- `true`: autosave resolves a name the same way a bare `:Session save`
  -- does (branch/project-aware when configured) -- a string pins autosave
  -- to that one fixed name regardless of project, `false` disables it
  -- despite `autosave = true`. Was a fixed string ("last") by default,
  -- which meant leaving any project silently overwrote every other
  -- project's autosave in that one shared slot -- see docs/configuration.md.
  autosave_name = true,
  metadata = true,
  -- Persist the per-tabpage buffer order (`vim.t.bufs`) that NvChad's
  -- tabufline and similar bars render from — `:mksession` cannot carry a
  -- tab-local variable, so a "move tab left/right" reordering is otherwise
  -- lost on load. No-op (and no sidecar written) when no tabline maintains
  -- such a list.
  restore_buffer_order = true,
  -- Attach `opts.title = "Sessions"` to `:Session`/autoload notify calls --
  -- picked up by any rich `vim.notify` backend (ui.nvim's `ui.notify`,
  -- nvim-notify, noice, snacks) that renders a title/colour from it.
  -- Costs nothing when none of those are installed/enabled: the default
  -- `:messages` echo just ignores an `opts` table it does not recognize.
  -- `false` opts out and calls `vim.notify` exactly as before.
  notify_title = true,
  hooks = {
    on_save = nil,
    on_load = nil,
  },
  blacklist = {
    buftypes = { "quickfix", "nofile", "prompt" },
    filetypes = { "gitcommit", "gitrebase" },
    -- Resolved by config/init.lua's M.setup() (platform-specific temp dir),
    -- unless the caller sets this explicitly -- see the module comment above.
    paths = {},
  },
  -- Optional normal-mode keymaps; `false` (the default) registers none.
  -- Set to a table of name -> lhs. Available names, one per `:Session`
  -- subcommand that takes no required argument, plus the picker:
  --   save, load, save_ts, list, current, picker, toggle_track,
  --   save_tab, load_tab, save_layout, load_layout
  -- `delete` and `rename` are deliberately absent: both require a name, and
  -- a bare keypress has nothing to pass. Use `picker` or the commands.
  --
  -- With `marks.enable = true` the list also takes: marks_menu, marks_edit,
  -- marks_add, marks_add_front, marks_pin, marks_remove, marks_sync,
  -- marks_debug -- and the numbered jumps come from `marks.select_key` /
  -- `marks.preview_key` below.
  keymaps = false,
  which_key = { enable = true },

  -- An ordered list of files to jump to by number, with a cursor position
  -- per file: `:Session marks`. Off unless a host turns it on.
  marks = {
    enable = false,
    -- "global": one list wherever Neovim runs. "project": one per project
    -- root (and branch, when `branch_aware` is on), like sessions.
    scope = "global",
    -- Paths seeded into the list on first use and restored by
    -- `:Session marks defaults reset`. Each entry is a list of path
    -- segments -- the first may be `$REPOS_DIR`, `$HOME` or `$NVIM_HOME`
    -- -- or one absolute string. Pins made at runtime layer on top.
    defaults = {},
    -- On the very first run, take over a harpoon v2 list (the bucket keyed
    -- by `stdpath("config")`, i.e. a single-global-list setup) before
    -- falling back to `defaults`. Also `:Session marks import-harpoon`.
    import_harpoon = true,
    -- Remember the cursor position of a marked file when its buffer is
    -- left, debounced by this many ms (0 = write at once).
    context_debounce_ms = 200,
    menu = {
      -- "auto": kit (ui.nvim's promptless list+preview -- no picker plugin
      -- needed), then snacks, then telescope, then fzf-lua, then the
      -- editable float. "edit" is the float itself; or name a picker.
      ui = "auto",
      pin_marker = "📌 pin", -- end-of-line flag on a default/pin in the float
      -- preview_keys: not set here on purpose (nil = the kit's own defaults:
      -- <C-f>/<C-p> scroll the preview, <Tab> hops into it, <CR> there opens
      -- the file at the cursor line). A table changes single groups, `false`
      -- turns them off -- see docs/marks.md.
    },
    preview = {
      max_kb = 1536, -- larger files show only the first `max_lines`
      max_lines = 4000,
    },
    -- Templates with one `%d` for 1..9: `select_key = "<leader>%d"` binds
    -- <leader>1..<leader>9 to jump, `preview_key = "<M-%d>"` to preview.
    -- Off by default.
    select_key = false,
    preview_key = false,
  },

  -- A persistent editor-corner indicator (ui.kit.chip) mirroring
  -- sessions.statusline.component(), alongside the one-shot notify on
  -- save/load/autoload rather than instead of it. Off by default; soft
  -- dependency on ui.kit -- does nothing when it isn't installed, same as
  -- the `autoload = "ask"` confirm float's own fallback. See docs/statusline.md.
  chip = {
    enable = false,
    anchor = "bottom-left", -- "bottom-left" | "bottom-right" | "top-left" | "top-right"
    shape = "rounded", -- "rounded" | "rect"
    color = nil, -- a highlight-group name, or { fg = "#...", bg = "#..." }; nil = kit's own default
    -- Flash the chip's colour on save/load/autoload, on top of the
    -- persistent state. `false` keeps the chip's colour steady.
    pulse = true,
    pulse_color = nil, -- nil = kit.chip.pulse's own default ("DiagnosticWarn")
    pulse_duration_ms = nil, -- nil = kit.chip.pulse's own default (300)
  },
}
