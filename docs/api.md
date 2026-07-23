# Public API

```lua
local S = require("sessions")

S.setup(opts?)                        -- configure and activate (idempotent)
S.save(name?)   → ok, path_or_err    -- save; nil name = auto-resolve
S.load(name?)   → ok, path_or_err, hidden_bufs
S.list()        → string[]           -- absolute paths of all .vim files
S.delete(name)  → ok, err            -- delete session + metadata
S.rename(old, new) → ok, err
S.current()     → string|nil         -- active session name (statusline use)
S.metadata(name) → Sessions.Meta|nil -- { saved_at, cwd, branch, buffers }
S.pick()                             -- open the session picker (see docs/picker.md)
```

## Statusline

`require("sessions.statusline").component(opts?)` returns a ready-made
string: the active session name, with a dirty marker appended when the
session's window/buffer layout has changed since the last save/load (i.e.
what the next autosave would capture). Returns `""` when no session is
active.

```lua
---@class Sessions.StatuslineOpts
---@field icon? string        Prefix before the session name (default "")
---@field dirty_icon? string  Suffix when layout changed since last save (default " *")
---@field empty? string       Returned when no session is active (default "")
```

```lua
-- lualine
require("lualine").setup({
  sections = {
    lualine_c = {
      function() return require("sessions.statusline").component() end,
    },
  },
})

-- heirline
{ provider = function() return require("sessions.statusline").component({ icon = " " }) end }
```
