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
```

## Statusline example

```lua
require("lualine").setup({
  sections = {
    lualine_c = {
      function()
        local name = require("sessions").current()
        return name and (" " .. name) or ""
      end,
    },
  },
})
```
