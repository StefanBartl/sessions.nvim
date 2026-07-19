# sessions.nvim — Bindings

Keymaps are disabled by default (`keymaps = false`); pass a table to
`setup()` to enable any subset of them. Each mapping carries a `desc`, so it
shows up in which-key (if installed) and `:map` without further work. A
"Session" group label is registered with which-key automatically when
`which_key.enable = true` (default) and at least one keymap is configured.

## Keymaps

| Mode | Config key | Suggested lhs   | Action |
|------|------------|------------------|--------|
| n    | `save`     | `<leader>ssa`    | `:SessionSave` |
| n    | `load`     | `<leader>slo`    | `:SessionLoad` |
| n    | `save_ts`  | `<leader>sst`    | Save with a timestamp suffix (`sess-YYYYMMDD-HHMMSS`) |
| n    | `list`     | `<leader>sli`    | `:SessionList` |

Defined in `lua/sessions/bindings/keymaps/init.lua`. There are no defaults for the lhs
strings themselves — every mapping is opt-in and only attached if you set it.

## User commands

| Command                | Purpose |
|--------------------------|---------|
| `:SessionSave [name]`     | Save a session (tab-completes to overwrite an existing one) |
| `:SessionSaveTimestamp`   | Save with a timestamp suffix |
| `:SessionLoad [name]`     | Load a session |
| `:SessionDelete <name>`   | Delete a session by name |
| `:SessionRename <old> <new>` | Rename a session |
| `:SessionList`            | List all saved sessions |
| `:SessionCurrent`         | Print the active session name |
| `:SessionToggleTrack [name]` | Toggle git `skip-worktree` on a session file, so named sessions can live in a config repo without being committed on machines where the paths don't exist |

All defined in `lua/sessions/bindings/usercmds/init.lua`; registered
unconditionally by `setup()`.

## Autocmds

`lua/sessions/bindings/autocmds/init.lua` wires the autosave-on-exit and (if enabled)
autoload-on-enter behavior described in
[Configuration](configuration.md#autoload--autosave) — see that file for the
exact `autoload`/`autosave` semantics.
