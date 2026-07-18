# Configuration

All options and their defaults:

```lua
require("sessions").setup({
  -- Directory where session files are stored.
  root = vim.fn.stdpath("data") .. "/sessions",

  -- Session name used when auto-resolution yields nothing.
  default_name = "last",

  -- Append the current git branch to the auto-resolved session name.
  branch_aware = true,

  -- Prefix the auto-resolved name with the detected project root basename.
  project_aware = true,

  -- Files searched upward from cwd to detect a project root.
  project_markers = {
    ".git", "pyproject.toml", "package.json",
    "Makefile", "Cargo.toml", "go.mod",
  },

  -- Passed to vim.opt.sessionoptions before every save/load.
  sessionoptions = "buffers,curdir,tabpages,winsize,help,folds",

  -- Auto-load the contextual session when Neovim starts without file args.
  autoload = false,

  -- Auto-save to a fixed session name on VimLeavePre (false = disabled).
  autosave = true,

  -- Session name for autosave (used when autosave = true).
  autosave_name = "last",

  -- Write a .{name}.json companion file next to each session.
  metadata = true,

  -- Callbacks invoked after save/load (errors are swallowed via pcall).
  hooks = {
    on_save = nil, -- fun(name: string, path: string)
    on_load = nil, -- fun(name: string, path: string)
  },

  -- Buffers matching these are wiped before :mksession.
  blacklist = {
    buftypes  = { "quickfix", "nofile", "prompt" },
    filetypes = { "gitcommit", "gitrebase" },
    paths     = { "/tmp/", "/private/tmp/" },
    -- %TEMP% is automatically added on Windows.
  },

  -- Normal-mode keymaps. Disabled by default. Set to a table to enable:
  keymaps = false, -- or { save = "<leader>ssa", load = "<leader>slo", ... }
})
```

## Session Naming

When no explicit name is given, the name is resolved from context:

| `project_aware` | `branch_aware` | Result |
|---|---|---|
| ✓ | ✓ | `myapp_feature-login` |
| ✓ | ✗ | `myapp` |
| ✗ | ✓ | `feature-login` |
| ✗ | ✗ | `last` (default_name) |

Unsafe filename characters (`/`, `\`, spaces) are replaced with `-` or `_`.
`feature/login` → `feature-login`.
