# Public API

```lua
local S = require("sessions")

S.setup(opts?)                        -- configure and activate (idempotent)
S.save(name?)   → ok, path_or_err    -- save; nil name = auto-resolve
S.load(name?)   → ok, path_or_err, hidden_bufs
S.list()        → string[]           -- absolute paths of all .vim files
S.delete(name)  → ok, err            -- delete session + metadata + buffer-order sidecar
S.rename(old, new) → ok, err
S.current()     → string|nil         -- active session name (statusline use)
S.metadata(name) → Sessions.Meta|nil -- { saved_at, cwd, branch, buffers }
S.pick()                             -- open the session picker (see docs/picker.md)
```

## Statusline

`require("sessions.statusline").component(opts?)` returns a ready-made string:
the active session name, with a dirty marker appended when the window and
buffer layout has changed since the last save or load. It returns `""` when no
session is active, and is safe to call on every redraw.

Its options, the lualine/heirline/native wiring, what "dirty" means and why the
component is cheap enough for a hotpath are in
[statusline.md](statusline.md).
