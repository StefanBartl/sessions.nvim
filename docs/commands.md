# Commands

One command, `:Session <subcommand>` (built via
[`lib.nvim.usercmd.composer`](https://github.com/StefanBartl/lib.nvim), with
`<Tab>` completion — session-name args complete dynamically), plus a
standalone `:LastSession` convenience command.

| Command | Description |
|---|---|
| `:Session save [name]` | Save session (auto-named if omitted) |
| `:Session save-timestamp` | Save with a `sess-YYYYMMDD-HHMMSS` suffix |
| `:Session load [name]` | Load session (tab-completes saved names); omitted name loads the remembered last-loaded session, or `default_name` |
| `:Session delete <name>` | Delete session + companion metadata |
| `:Session rename <old> <new>` | Rename session + companion metadata |
| `:Session list` | List sessions with timestamp and branch |
| `:Session current` | Print the active session name |
| `:Session toggle-track [name]` | Toggle `git skip-worktree` on a session file |
| `:Session save-tab [name]` | Save only the current tab's window layout (stored separately from full sessions) |
| `:Session load-tab <name>` | Load a tab session into a new tab, leaving other tabs untouched |
| `:Session save-layout <name>` | Save the current window-split structure only (no buffers/files) |
| `:Session load-layout <name>` | Restore a window-split layout onto whatever buffers are currently open |
| `:LastSession` | Load the "last" session — convenience layer over `:Session load last`, unquoted-CLI-friendly (`nvim +LastSession`) |
| `:SessionLoad` | Open a session picker with live preview (Snacks.picker or Telescope) — see [Picker Integration](picker.md) |

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
