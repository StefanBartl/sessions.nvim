# What you get with the defaults

| Command | Does |
| --- | --- |
| `:Session save` / `load` | Save or restore, auto-resolved by project and branch |
| `:Session delete` / `rename` | The lifecycle commands most session plugins leave out |
| `:LastSession` | Wherever you left off — project/branch-aware, remembered across restarts |
| `:SessionLoad` | The picker: live preview, multi-select delete |
| `:Session save-tab` / `load-tab` | Just the current tab's windows, independent of the rest |
| `:Session save-layout` / `load-layout` | Reapply a split arrangement to whatever is open, without touching buffers |
| `:Session toggle-track` | Flip `git skip-worktree` on a session file, for syncing named sessions |

Keymaps are off by default — [BINDINGS.md](BINDINGS.md) is both the
inventory and the list of what to switch on. Every option, including
`autoload = "ask"` for the y/n prompt on startup, is
[configuration.md](configuration.md).

`require("sessions.statusline").component()` returns the active session name
with a dirty marker when the layout has changed since the last save. See
[statusline.md](statusline.md) for the options and the lualine, heirline and
native wiring.
