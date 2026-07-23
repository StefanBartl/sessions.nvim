# Cross-device Portability

`:mksession` already writes buffer paths relative to `cwd` when possible
(with `curdir` in `sessionoptions`, the default), but the embedded `cd`
line and any paths outside `cwd` stay absolute to the machine that saved
them. Two options close that gap for sessions synced across machines/OSes
(e.g. via `:Session toggle-track` — see [Git Integration](git-integration.md)).

## `relative_paths`

```lua
require("sessions").setup({
  relative_paths = true,
})
```

On save, every occurrence of the save-time `cwd` in the `.vim` file is
replaced with a portable placeholder. On load, the placeholder is
re-anchored to *whatever the current `cwd` is* — so load a portable
session from within the project directory you want it to apply to.

The stored `.vim` file itself is rewritten at save time (so it's what gets
synced/committed); loading never mutates it.

## `root_remap`

```lua
require("sessions").setup({
  root_remap = {
    ["/home/user"] = "/Users/user",   -- Linux session, loaded on macOS
    ["C:/Users/alice"] = "/home/alice", -- Windows session, loaded on Linux/WSL
  },
})
```

A table of old-root → new-root path prefixes, applied on load only. Useful
when `relative_paths` isn't enabled (or doesn't cover a path outside
`cwd`) and you know the exact prefix substitution needed between machines.

Rewriting happens on an in-memory temp copy sourced instead of the
original file — the stored session stays untouched, so it keeps working
for every machine in your `root_remap` set, not just the last one that
loaded it.
