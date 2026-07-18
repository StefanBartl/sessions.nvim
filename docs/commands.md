# Commands

| Command | Description |
|---|---|
| `:SessionSave [name]` | Save session (auto-named if omitted) |
| `:SessionSaveTimestamp` | Save with a `sess-YYYYMMDD-HHMMSS` suffix |
| `:SessionLoad [name]` | Load session (tab-completes saved names) |
| `:SessionDelete <name>` | Delete session + companion metadata |
| `:SessionRename <old> <new>` | Rename session + companion metadata |
| `:SessionList` | List sessions with timestamp and branch |
| `:SessionCurrent` | Print the active session name |
| `:SessionToggleTrack [name]` | Toggle `git skip-worktree` on a session file |

## Keymaps

Keymaps are **disabled by default**. Enable them in your setup:

```lua
require("sessions").setup({
  keymaps = {
    save    = "<leader>ssa",
    load    = "<leader>slo",
    save_ts = "<leader>sst",
    list    = "<leader>sli",
  },
})
```

Or disable individual keymaps:
```lua
keymaps = {
  save = "<leader>ssa",
  load = false,  -- disabled
  -- ...
}
```
