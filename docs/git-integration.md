# Git Integration

`:Session toggle-track` solves the cross-device sync dilemma:

- You want named sessions (e.g. `myapp_main`) committed to your config repo
  so they sync to other machines.
- You do **not** want `last.vim` committed because its absolute paths only
  exist on the current machine and cause errors on others.

## Setup

```lua
require("sessions").setup({
  root = vim.fn.stdpath("config") .. "/sessions",
})
```

Run `:Session toggle-track last` once to mark `last.vim` as skip-worktree.
The file stays on disk, but git ignores changes to it. Run again to un-skip.
