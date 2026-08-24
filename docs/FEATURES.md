# Features

Branch- and project-aware session management built on Neovim's own
`:mksession`/`:source`, via a single `:Session <subcommand>` command.

## Branch- and project-aware naming

Auto-resolves a session name from the current project root (nearest
`.git`, `package.json`, `Makefile`, `Cargo.toml`, `go.mod`, ...) and git
branch when no explicit name is given to `:Session save`, e.g.
`myapp_feature-login`. Only governs saving with an omitted name — loading
with an omitted name instead prefers the remembered last-loaded session.

- **Module:** `lua/sessions/init.lua`, `lua/sessions/git.lua`
- **Config:** `opts.branch_aware` (default `true`), `opts.project_aware`
  (default `true`), `opts.project_markers`

## Save, load, delete, rename, list

The core lifecycle around `:mksession`/`:source`, wrapped with name
resolution and metadata.

- **Module:** `lua/sessions/init.lua` (`save`, `load`, `delete`, `rename`,
  `list`, `current`)
- **Usercmds:** `:Session save [name]`, `:Session save-timestamp`,
  `:Session load [name]`, `:Session delete <name>`,
  `:Session rename <old> <new>`, `:Session list`, `:Session current`
- **Keymaps:** one per `:Session` subcommand that takes no required
  argument, plus the picker — `save`, `load`, `save_ts`, `list`, `current`,
  `picker` (`:SessionLoad`), `toggle_track`, `save_tab`, `load_tab`,
  `save_layout`, `load_layout`. All disabled by default.

  Extended 2026-08-24, closing the flag/option audit's entry about `current`
  and the picker having no keymap. The list had been a hardcoded four while
  the command grew to twelve subcommands. `delete` and `rename` stay out, and
  the reason is sharper than the audit's guess of "destructive/rare": both
  require a name argument, and a keymap is a bare keypress with nothing to
  pass. Configuring one reports that specifically instead of "unknown key",
  since it is a real subcommand rather than a typo.

## Clean save

Blacklisted buffer types (`quickfix`, `nofile`, `prompt`), filetypes
(`gitcommit`, `gitrebase`), and path prefixes (`/tmp/`, `/private/tmp/`,
plus `%TEMP%` auto-added on Windows) are wiped from the buffer list before
`:mksession` runs, so a saved session doesn't reload quickfix noise or
scratch/temp buffers.

- **Config:** `opts.blacklist.{buftypes,filetypes,paths}`

## E445 fix on load

Modified buffers are hidden rather than discarded before loading a new
session, so the session file's internal `only`/`tabonly` commands never hit
Neovim's `E445: Other window contains changes` error.

- **Module:** `lua/sessions/init.lua`

## Metadata companion file

A hidden `.{name}.json` written alongside each session's `.vim` file with
the save timestamp, `cwd`, git branch, and buffer list — used by
`:Session list` and the picker preview, and readable directly via the
public API.

- **Module:** `lua/sessions/metadata.lua`
- **Config:** `opts.metadata` (default `true`)
- **API:** `require("sessions").metadata(name)`

## Autoload / autosave

Loads the contextual session automatically on a plain `nvim` start (no
file args), and saves to a fixed name on `VimLeavePre`.

- **Module:** `lua/sessions/bindings/autocmds/init.lua`
- **Config:** `opts.autoload` (default `false`; `"ask"` shows a floating
  y/n confirmation before loading instead of loading silently),
  `opts.autosave` (default `true`), `opts.autosave_name` (default `"last"`)

## Remembered last-loaded session

The name most recently passed to a successful `:Session load <name>` is
persisted in `root/.state.json`, surviving restarts. `:Session load` (no
name) and autoload prefer this over the auto-resolved project+branch name,
falling back to `opts.default_name` if nothing has ever been loaded or the
remembered session no longer exists on disk.

- **Module:** `lua/sessions/init.lua`
- **Config:** `opts.default_name` (default `"last"`)

## Lifecycle commands: delete / rename / toggle-track

Session management commands most `:mksession` wrappers don't provide.
`toggle-track` flips git `skip-worktree` on a session file, so named
sessions can be committed to a dotfiles/config repo for cross-machine sync
without the machine-local `last.vim` being committed too.

- **Usercmds:** `:Session delete <name>`, `:Session rename <old> <new>`,
  `:Session toggle-track [name]`

## Portability: `relative_paths` / `root_remap`

`relative_paths` rewrites the save-time `cwd` in the `.vim` file to a
portable placeholder, re-anchored to whatever `cwd` is at load time.
`root_remap` applies old-root → new-root path-prefix substitutions on load
only, on an in-memory copy — the stored session file is never mutated by
loading, so it keeps working across every machine in the remap set.

- **Config:** `opts.relative_paths` (default `false`), `opts.root_remap`
  (default `{}`)

## Tab-scoped sessions

Saves/restores only the current tab's window layout, stored separately
under `root/.tabs/` so it never collides with full sessions in
`:Session list`. Loading opens a new tab and restores into it, leaving
other tabs untouched — unlike `:Session load`, which collapses to a single
tab.

- **Usercmds:** `:Session save-tab [name]`, `:Session load-tab <name>`

## Window-layout snapshots

Captures just the split structure (row/column arrangement, window sizes)
of the current tab, not which buffers are open — for reapplying a favorite
pane layout to whatever files happen to be open. Stored as JSON under
`root/layouts/`.

- **Usercmds:** `:Session save-layout <name>`, `:Session load-layout <name>`

## Statusline component

A ready-made string for lualine/heirline: active session name plus a dirty
marker when the window/buffer layout has changed since the last save/load.

- **Module:** `lua/sessions/statusline.lua` (`component`)
- **API:** `require("sessions.statusline").component(opts?)`

## Session picker

`:SessionLoad` opens a session list with live preview (buffer list, save
timestamp, branch, cwd) and multi-select delete, backed by Snacks.picker if
available, else Telescope — neither is a hard dependency, and every other
`:Session` command works without either installed.

- **Module:** `lua/sessions/picker.lua`
- **Usercmds:** `:SessionLoad`
- **API:** `require("sessions").pick()`

## `:LastSession`

A standalone convenience command over `:Session load last`, so
`nvim +LastSession` works from the CLI without the quoting `:Session load`
needs for its two-word form.

- **Usercmds:** `:LastSession`

## `:checkhealth sessions`

Reports Neovim version compatibility, optional dependency status, active
configuration, session root accessibility, session count, and command
registration.

- **Module:** `lua/sessions/health.lua`
