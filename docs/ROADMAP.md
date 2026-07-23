# sessions.nvim — ROADMAP

## Planned

### Picker Integration
- `:SessionLoad` via Snacks.picker or Telescope with live preview
- Preview shows buffer list + timestamp + branch from metadata
- Multi-select delete

### Session Scoping
- **Tab-scoped sessions** — save/restore only the current tab's windows
- **Window-layout snapshots** — separate from full sessions, restore only splits

## Deferred / Under Consideration

- **Telescope extension** with session preview sidebar
- **`SessionRestore`** alias for `:SessionLoad` for discoverability
- **Session groups** — tag sessions and batch-load a group
- **Encrypted sessions** — not feasible without external tools; document workaround
