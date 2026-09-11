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
  keymaps = false, -- or { save = "<leader>ssa", picker = "<leader>spi", ... }

  -- Register a which-key group label for the keymap prefix, if which-key
  -- is installed and at least one keymap is configured.
  which_key = { enable = true },
})
```

## Session Naming

When no explicit name is given, the name is resolved from context:

| `project_aware` | `branch_aware` | Result |
|---|---|---|
| ✓ | ✓ | `myapp_feature-login` |
| ✓ | ✗ | `myapp` |
| ✗ | ✓ | `feature-login` |
| ✗ | ✗ | `last` (default_name) |

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
