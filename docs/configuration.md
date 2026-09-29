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

  -- Persist per-tabpage tab-pin state (ui.nvim's tabline pinned-buffer
  -- list, `vim.t.ui_pinned`) -- that module does not persist it itself.
  -- Same shape as restore_buffer_order above (`.{name}.pins.json` sidecar,
  -- no-op without ui.nvim), and restored right after it: pin restore
  -- needs the buffer-order restore's final, stable bufnr mapping for the
  -- tab, not the one :mksession alone left behind.
  restore_pinned_buffers = true,

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

  -- An editor-corner indicator (ui.kit.chip) mirroring the same text as
  -- sessions.statusline.component(). On by default; soft dependency on
  -- ui.kit -- does nothing when it isn't installed, so this default is a
  -- no-op without it. While it is actually shown, it REPLACES the notify
  -- above instead of showing alongside it -- only one session-status
  -- indicator at a time. See docs/statusline.md.
  chip = {
    enable = true,
    anchor = "bottom-left",      -- bottom-right | top-left | top-right -- switching to a right-side anchor auto-falls-back shape from "dock_left" to "rounded_chip" (see shape below), so it never renders backwards
    shape = "dock_left",         -- dock_left (rounded except the LEFT edge -- only correct at a left anchor, pairs with dock below) | rounded_chip (bordered capsule) | chip (flat, borderless block) | classic (no box at all); old names (rounded/rect/text) still work
    color = nil,                 -- a highlight-group name, { fg = "#...", bg = "#..." }, or a zero-arg function returning either
    dock = true,                 -- sit flush on the statusline row (no gap) instead of floating just above it; degrades to the ordinary placement without a real statusline row, safe either way
    track_mode = false,          -- refresh the chip on every mode change -- only useful paired with a `color` function that itself tracks the mode
    row_offset = nil,            -- integer, nil/0 = no change -- a plain per-setup nudge added to the computed row, e.g. to fine-tune position for your own terminal/font. Cannot reach past your terminal's own outer padding (e.g. WezTerm's window_padding) -- that sits outside anything Neovim can draw into. A fractional value is accepted but Neovim itself always rounds it DOWN to the nearest integer (`:h nvim_open_win()`), so e.g. 0.5 lands on the same row/col as 0 -- use a whole number
    col_offset = nil,            -- same as row_offset, for the column. Note: shape "dock_left" (the default) falls back to "rounded_chip" whenever col_offset would actually move the chip (its floored value isn't 0) -- dock_left's own left border is intentionally blank, correct only flush against the screen edge
    min_width = nil,             -- integer, nil/0 = no minimum -- a floor under the chip's own content-derived width (longest rendered line + 2), for when a short line (e.g. one glyph) renders visibly cramped. Content wider than it still grows the box past it
    text = "modern",             -- "modern" (icon + folder, then icon + branch, live -- not a parse of the resolved name) | "classic_text" (today's plain resolved name) | a table for full control -- see "Chip text" in docs/statusline.md
    timeout_ms = 3000,           -- ms before it auto-hides; false (or <= 0) = stay up permanently
    pulse = true,                -- flash the chip's colour on save/load/autoload
    pulse_color = nil,           -- nil = kit.chip.pulse's own default ("DiagnosticWarn")
    pulse_duration_ms = nil,     -- nil = kit.chip.pulse's own default (300)
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

The naming table above governs `:Session load [name]` when a name *is*
given, and `:Session save [name]` (no name given) *only while nothing is
currently loaded/saved this session* — as soon as you've loaded or saved
any session (explicitly named or auto-resolved), a bare `:Session save`
targets that one instead of re-deriving from the naming table. Load
`nvim_main`, then explicitly save a second copy as `nvim_main_2`, then a
bare `:Session save` afterwards updates `nvim_main_2` — not `nvim_main` and
not a fresh auto-resolved name — because `nvim_main_2` is what you're
actually in. `:Session current` shows which one that is. A bare
`:Session load` (no name) and autoload instead resolve in this order:

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
