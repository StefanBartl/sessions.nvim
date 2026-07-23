# Metadata

When `metadata = true` a hidden `.{name}.json` is written alongside each
`.vim` file:

```json
{
  "saved_at": "2025-12-31T12:00:00Z",
  "cwd":      "/home/user/myapp",
  "branch":   "feature/login",
  "buffers":  ["/home/user/myapp/src/main.lua"]
}
```

`branch` is only populated when `branch_aware` or `project_aware` is enabled
(sessions.git is lazy-loaded and never shells out to `git` otherwise).

Used by `:Session list` for timestamps and branch display. Access it in Lua:
```lua
local meta = require("sessions").metadata("myapp_feature-login")
-- meta.saved_at, meta.branch, meta.buffers, ...
```
