# Features

Neovim can already save a session. What it cannot do is decide *which* one:
`:mksession` writes wherever you point it, and every workflow built on it ends
up as a naming convention held together by hand. This plugin makes the name a
function of where you are.

| Area | Does |
| --- | --- |
| **Naming** | The project root — `.git`, `package.json`, and the rest — plus the current git branch. Switch branches and a different workspace comes back |
| **Lifecycle** | `save`, `load`, `delete` and `rename`, the last two missing from most session plugins, plus autosave on exit and an `autoload = "ask"` prompt on start |
| **Clean saves** | Blacklisted buffer types, filetypes and path prefixes are wiped before `:mksession` — no quickfix noise, no temp files in tomorrow's session |
| **Portability** | `relative_paths` re-anchors a session wherever it is loaded, and `root_remap` translates absolute prefixes across machines and operating systems |
| **Scoping** | `save-tab` / `load-tab` for one tab's windows, and `save-layout` / `load-layout` to reapply a split arrangement to whatever is already open |
| **Metadata** | A companion `.json` recording the save timestamp, branch and buffer list, for a picker or a statusline to read without sourcing anything |
| **Sync** | `:Session toggle-track` flips `git skip-worktree` on a session file, so named sessions travel through your config repo without committing transient state |

Two details that exist because the obvious implementation gets them wrong:
modified buffers are **hidden rather than discarded** before a load, so the
session's own `only` / `tabonly` never triggers E445; and NvChad tabufline's
`vim.t.bufs` ordering — which `:mksession` cannot carry — is persisted in a
sidecar and reapplied, a no-op if you do not use such a tabline.

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

## Tabline buffer order (`vim.t.bufs`)

NvChad's tabufline — and any tabline that renders from an ordered
`vim.t.bufs` list of buffer numbers — keeps the bar's left-to-right order
in that tab-local variable. `:mksession` serializes buffers, windows and
tabpages, but never a tab-local variable, so a manual "move tab
left/right" reordering is lost the moment a session is loaded.

sessions.nvim captures each tabpage's `vim.t.bufs` (as buffer names) into a
hidden `.{name}.bufs.json` sidecar on save and reapplies it right after
`:source`. A buffer open in a tab but missing from the saved order is kept
(appended); a saved name with no live buffer is dropped. It is a complete
no-op — and writes no sidecar — when nothing maintains a `vim.t.bufs`
list, so a non-tabufline setup pays nothing.

- **Module:** `lua/sessions/buforder.lua`
- **Config:** `opts.restore_buffer_order` (default `true`)

## Autoload / autosave

Loads the contextual session automatically on a plain `nvim` start (no
file args), and saves on `VimLeavePre`. Autosave's target follows
`opts.autosave_name`: `true` (the default) auto-resolves branch/project-
aware just like a bare `:Session save`, so leaving one project doesn't
clobber another's autosave in a shared fixed slot; a string pins it to that
one name regardless of project.

- **Module:** `lua/sessions/bindings/autocmds/init.lua`
- **Config:** `opts.autoload` (default `false`; `"ask"` shows a floating
  y/n confirmation before loading instead of loading silently),
  `opts.autosave` (default `true`), `opts.autosave_name` (default `true`;
  a string pins it to a fixed name, `false` disables autosave)

## Remembered last-loaded session

The name most recently passed to a successful `:Session load <name>` or
resolved by a successful `:Session save`/autosave is persisted in
`root/.state.json`, surviving restarts. A bare `:Session load` (no name)
and autoload check this only *after* the current project's own
auto-resolved session (see docs/configuration.md's "Session Naming"): the
remembered pointer is one value shared by every project, so it wins only
when project/branch-aware naming is off or the current project has no
saved session of its own yet. Falls back to `opts.default_name` if neither
resolves to a file that exists.

- **Module:** `lua/sessions/init.lua`, `lua/sessions/core.lua` (resolution),
  `lua/sessions/state.lua` (persistence)
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

## Marks

An ordered list of files jumped to by number — `:Session marks select 3`,
or `<leader>3` once `marks.select_key` is set — with the cursor position
remembered per file. Three kinds of entry: marks (the live list), defaults
(`marks.defaults` in the config, `$REPOS_DIR`/`$HOME`/`$NVIM_HOME`-relative
so one config serves every machine) and pins (runtime defaults, stored on
this machine only). Defaults and pins are seeded once and come back on
`defaults sync`; a mark you delete stays deleted. One list for everything by
default (`scope = "global"`), or one per project and branch. An editable
float (reorder, delete, paste), snacks/telescope/fzf pickers with shortened
labels, a read-only preview, and a one-time import of a harpoon v2 list.
Off by default.

- **Module:** `lua/sessions/marks/` (`init.lua` store and operations,
  `menu.lua`, `preview.lua`)
- **Usercmds:** `:Session marks …` — see [marks.md](marks.md)
- **Keymaps:** `marks_menu`, `marks_edit`, `marks_add`, `marks_add_front`,
  `marks_pin`, `marks_remove`, `marks_sync`, `marks_debug`, plus the
  `select_key`/`preview_key` templates for 1–9
- **Config:** `opts.marks` (default `enable = false`)

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
