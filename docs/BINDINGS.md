# sessions.nvim — Bindings

Keymaps are disabled by default (`keymaps = false`); pass a table to
`setup()` to enable any subset of them. Each mapping carries a `desc`, so it
shows up in which-key (if installed) and `:map` without further work. A
"Session" group label is registered with which-key automatically when
`which_key.enable = true` (default) and at least one keymap is configured.

## Keymaps

| Mode | Config key      | Suggested lhs   | Action |
|------|-----------------|------------------|--------|
| n    | `save`          | `<leader>ssa`    | `:Session save` |
| n    | `load`          | `<leader>slo`    | `:Session load` |
| n    | `save_ts`       | `<leader>sst`    | `:Session save-timestamp` (`sess-YYYYMMDD-HHMMSS`) |
| n    | `list`          | `<leader>sli`    | `:Session list` |
| n    | `current`       | `<leader>scu`    | `:Session current` |
| n    | `picker`        | `<leader>spi`    | `:SessionLoad` — picker with live preview |
| n    | `toggle_track`  | `<leader>stg`    | `:Session toggle-track` |
| n    | `save_tab`      | `<leader>sta`    | `:Session save-tab` |
| n    | `load_tab`      | `<leader>slt`    | `:Session load-tab` |
| n    | `save_layout`   | `<leader>sly`    | `:Session save-layout` |
| n    | `load_layout`   | `<leader>sll`    | `:Session load-layout` |

Defined in `lua/sessions/bindings/keymaps/init.lua`. There are no defaults for the lhs
strings themselves — every mapping is opt-in and only attached if you set it.

### Why `delete` and `rename` have no keymap

Every `:Session` subcommand that takes no **required** argument is mappable;
`delete` and `rename` are the two that aren't, and that is the whole reason
they are missing. `:Session delete <name>` needs a name and a bare keypress
has nothing to pass. It is not about them being destructive — `:Session save`
overwrites just as readily and is mappable.

Setting `keymaps.delete` says so explicitly rather than reporting an unknown
key, since it is a real subcommand and not a typo. Use `picker`
(`:SessionLoad`) or the commands directly.

## User commands

One command, `:Session <subcommand>` (built via
[`lib.nvim.usercmd.composer`](https://github.com/StefanBartl/lib.nvim), with
`<Tab>` completion), plus a standalone `:LastSession` convenience command.

| Command                | Purpose |
|--------------------------|---------|
| `:Session save [name]`     | Save a session (tab-completes to overwrite an existing one) |
| `:Session save-timestamp`   | Save with a timestamp suffix |
| `:Session load [name]`     | Load a session |
| `:Session delete <name>`   | Delete a session by name |
| `:Session rename <old> <new>` | Rename a session |
| `:Session list`            | List all saved sessions |
| `:Session current`         | Print the active session name |
| `:Session toggle-track [name]` | Toggle git `skip-worktree` on a session file, so named sessions can live in a config repo without being committed on machines where the paths don't exist |
| `:Session save-tab [name]` | Save only the current tab's window layout, stored separately under `root/.tabs/` (see [Session Scoping](session-scoping.md)) |
| `:Session load-tab <name>` | Load a tab session into a new tab, leaving other tabs untouched |
| `:Session save-layout <name>` | Save the current window-split structure only, no buffers/files |
| `:Session load-layout <name>` | Restore a window-split layout onto whatever buffers are currently open |
| `:LastSession`             | Load the session named "last" — pure convenience layer over `:Session load last`, so `nvim +LastSession` works without CLI-arg quoting |
| `:SessionLoad`             | Open a session picker with live preview (Snacks.picker or Telescope) — see [Picker Integration](picker.md) |

All defined in `lua/sessions/bindings/usercmds/init.lua`; registered
unconditionally by `setup()`. Session-name arguments (`save`/`load`/`delete`/
`rename`/`toggle-track`) tab-complete dynamically from the current list of
saved sessions; `save-tab`/`load-tab` and `save-layout`/`load-layout`
tab-complete from their own separate name lists.

## Autocmds

`lua/sessions/bindings/autocmds/init.lua` wires the autosave-on-exit and (if enabled)
autoload-on-enter behavior described in
[Configuration](configuration.md#autoload--autosave) — see that file for the
exact `autoload`/`autosave` semantics.
