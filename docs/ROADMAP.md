# sessions.nvim — ROADMAP

## Planned

### Picker Integration
- `:SessionLoad` via Snacks.picker or Telescope with live preview
- Preview shows buffer list + timestamp + branch from metadata
- Multi-select delete

### Autoload Improvements
- `autoload = "ask"` mode: show a floating prompt "Restore session X?" on startup
- Remember last-loaded session across restarts via a small state file

### Session Scoping
- **Tab-scoped sessions** — save/restore only the current tab's windows
- **Window-layout snapshots** — separate from full sessions, restore only splits

### Statusline Integration
- Dedicated `require("sessions.statusline").component()` for lualine/heirline
- Shows: session name + dirty indicator when autosave is pending

### Cross-device Portability
- `relative_paths` option: store paths relative to cwd in the .vim file (requires path rewriting)
- `root_remap` config: `{ ["/home/user"] = "/Users/user" }` for cross-OS sync

### Performance
- Lazy-load `sessions.git` only when `branch_aware` or `project_aware` is enabled

## Deferred / Under Consideration

- **Telescope extension** with session preview sidebar
- **`SessionRestore`** alias for `:SessionLoad` for discoverability
- **Session groups** — tag sessions and batch-load a group
- **Encrypted sessions** — not feasible without external tools; document workaround
