# Configuration

All options and their defaults:

```lua
require("sessions").setup({
  -- Directory where session files are stored.
  root = vim.fn.stdpath("data") .. "/sessions",

  -- Session name used when auto-resolution yields nothing.
  default_name = "last",

  -- Append the current git branch to the auto-resolved session name.
  branch_aware = true,

  -- Prefix the auto-resolved name with the detected project root basename.
  project_aware = true,

  -- Files searched upward from cwd to detect a project root.
  project_markers = {
    ".git", "pyproject.toml", "package.json",
    "Makefile", "Cargo.toml", "go.mod",
  },

  -- Passed to vim.opt.sessionoptions before every save/load.
  sessionoptions = "buffers,curdir,tabpages,winsize,help,folds",

  -- Rewrite the saved cwd to a portable placeholder, re-anchored to cwd on
  -- load. See docs/portability.md.
  relative_paths = false,

  -- Old-root -> new-root path prefixes translated when loading, for
  -- cross-OS/cross-machine sync. See docs/portability.md.
  root_remap = {},

  -- Auto-load the contextual session when Neovim starts without file args.
  -- Set to "ask" to show a floating y/n prompt before loading instead of
  -- loading silently.
  autoload = false,

  -- Auto-save on VimLeavePre (false = disabled).
  autosave = true,

  -- Autosave target, used when autosave = true:
  --   true    -- resolve the same way a bare `:Session save` does
  --             (branch/project-aware when configured above), so leaving
  --             one project doesn't overwrite another's autosave.
  --   "name"  -- pin autosave to this one fixed session regardless of
  --             project/branch (the old default's behavior).
  --   false   -- no autosave despite autosave = true.
  autosave_name = true,

  -- Write a .{name}.json companion file next to each session.
  metadata = true,

  -- Persist the per-tabpage buffer order that NvChad's tabufline (and any
  -- tabline rendering from an ordered `vim.t.bufs`) shows. `:mksession`
  -- cannot carry a tab-local variable, so a "move tab left/right"
  -- reordering is otherwise lost on load. Stored in a `.{name}.bufs.json`
  -- sidecar; a no-op that writes nothing when no such tabline is in use.
  restore_buffer_order = true,

  -- Attach opts.title = "Sessions" to :Session/autoload notify calls. A
  -- rich vim.notify backend (ui.nvim's ui.notify, nvim-notify, noice,
  -- snacks) can render a title/colour from it; the plain :messages echo
  -- ignores it. false calls vim.notify exactly as before.
  notify_title = true,

  -- Callbacks invoked after save/load (errors are swallowed via pcall).
  hooks = {
    on_save = nil, -- fun(name: string, path: string)
    on_load = nil, -- fun(name: string, path: string)
  },

  -- Buffers matching these are wiped before :mksession.
  blacklist = {
    buftypes  = { "quickfix", "nofile", "prompt" },
    filetypes = { "gitcommit", "gitrebase" },
    paths     = { "/tmp/", "/private/tmp/" },
    -- %TEMP% is automatically added on Windows.
  },

  -- Normal-mode keymaps. Disabled by default. Set to a table to enable:
  -- Names: save, load, save_ts, list, current, picker, toggle_track,
  -- save_tab, load_tab, save_layout, load_layout. (`delete`/`rename` take
  -- required arguments, so they cannot be mapped — use `picker`.)
  -- With marks on, also: marks_menu, marks_edit, marks_add, marks_add_front,
  -- marks_pin, marks_remove, marks_sync, marks_debug.
  keymaps = false, -- or { save = "<leader>ssa", picker = "<leader>spi", ... }

  -- Register a which-key group label for the keymap prefix, if which-key
  -- is installed and at least one keymap is configured.
  which_key = { enable = true },

  -- The mark list: an ordered set of files jumped to by number, with pins
  -- and defaults. Off by default — see docs/marks.md.
  marks = {
    enable = false,
    scope = "global",              -- "global": one list everywhere; "project": per root (and branch)
    defaults = {},                 -- seeded once, restored by `defaults reset`:
                                   --   { "$NVIM_HOME", "init.lua" }, { "$REPOS_DIR", "notes.md" }, "/abs/path"
    import_harpoon = true,         -- first run: take over harpoon's single-global-list bucket if found
    context_debounce_ms = 200,     -- cursor position remembered on BufLeave, this many ms later
    menu = {
      ui = "auto",                 -- auto (kit > snacks > telescope > fzf > edit) | edit | kit | snacks | telescope | fzf
      pin_marker = "📌 pin",       -- end-of-line flag on a default/pin in the edit float
      -- preview_keys = nil,       -- kit menu: keys of the preview pane (a table per group, or false); nil = defaults,
                                   --   <C-f>/<C-p> scroll it, <Tab> hops in, <CR> there opens at the cursor line (marks.md)
    },
    preview = { max_kb = 1536, max_lines = 4000 },
    select_key = false,            -- e.g. "<leader>%d": <leader>1..9 jump to entry N
    preview_key = false,           -- e.g. "<M-%d>":     <M-1>..9 preview entry N
  },
})
```

## Validation

`setup()` checks `opts` against the option shape above before merging it
onto the defaults. An unknown key (e.g. a typo like `keymaps.saev`) is
dropped and reported with a did-you-mean hint when one is close enough; a
value of the wrong shape (e.g. `project_markers = "x"` instead of a list, or
`blacklist = "x"` instead of a table) is dropped so the built-in default
takes effect instead of the option silently vanishing or crashing a module
downstream. Every issue found is listed by `:checkhealth sessions`.

## Session Naming

When no explicit name is given, the name is resolved from context:

| `project_aware` | `branch_aware` | Result |
|---|---|---|
| true | true | `myapp_feature-login` |
| true | false | `myapp` |
| false | true | `feature-login` |
| false | false | `last` (default_name) |

Unsafe filename characters (`/`, `\`, spaces) are replaced with `-` or `_`.
`feature/login` → `feature-login`.

The naming table above governs `:Session save [name]` (no name given), and
`:Session load [name]` when a name *is* given. A bare `:Session load` (no
name) and autoload instead resolve in this order:

1. **The auto-resolved name for the project/branch you're in right now** —
   the same result the naming table above gives a save — but only when that
   session's file actually exists; a project that was never saved has none
   to prefer.
2. **The remembered last-loaded/saved session**: the name most recently
   passed to a successful `:Session load <name>`, or auto-resolved by a
   `:Session save`/autosave — persisted in a small `.state.json` file in
   `root`, so it survives restarts. This one pointer is shared by every
   project, so it only wins when (1) has nothing to offer: `project_aware`
   and `branch_aware` are both off, or the current project has no saved
   session of its own yet.
3. **`default_name`**, if neither of the above resolves to a file that
   exists.

(1) is checked first deliberately: preferring the remembered pointer
unconditionally meant opening a *different* project with `autoload = true`
could silently load whatever session you last touched elsewhere — the file
still exists on disk, `.state.json` doesn't know it belongs to another
project. See `autosave_name` above for the matching autosave-side fix.
