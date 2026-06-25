```
  ███████╗███████╗███████╗███████╗██╗ ██████╗ ███╗   ██╗███████╗
  ██╔════╝██╔════╝██╔════╝██╔════╝██║██╔═══██╗████╗  ██║██╔════╝
  ███████╗█████╗  ███████╗███████╗██║██║   ██║██╔██╗ ██║███████╗
  ╚════██║██╔══╝  ╚════██║╚════██║██║██║   ██║██║╚██╗██║╚════██║
  ███████║███████╗███████║███████║██║╚██████╔╝██║ ╚████║███████║
  ╚══════╝╚══════╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
                                               .nvim
```

[![Neovim](https://img.shields.io/badge/Neovim-0.9+-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Branch- and project-aware Neovim sessions — no external dependencies beyond
the built-in `:mksession` / `:source`.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Keymaps](#keymaps)
- [Public API](#public-api)
- [Session Naming](#session-naming)
- [Metadata](#metadata)
- [Git Integration](#git-integration)
- [Health Check](#health-check)

---

## Features

- **Branch-aware** — session name automatically includes the current git branch, so switching branches restores a different workspace
- **Project-aware** — detects your project root (`.git`, `package.json`, …) and prefixes the session name
- **Metadata** — a companion `.json` records the save timestamp, branch, and buffer list for statuslines or pickers
- **Clean save** — blacklisted buffer types, filetypes, and path prefixes are wiped before `:mksession` (no quickfix noise, no temp files)
- **E445 fix** — modified buffers are hidden (not discarded) before loading, so the session's internal `only`/`tabonly` never triggers E445
- **`SessionDelete` / `SessionRename`** — lifecycle commands missing from most session plugins
- **`SessionToggleTrack`** — toggle `git skip-worktree` on a session file to sync named sessions via your config repo without committing transient state
- **`:checkhealth sessions`** — self-diagnostic for setup verification
- **Optional lib.nvim** — uses `lib.nvim.notify`, `lib.nvim.map`, and `lib.nvim.git` when available; falls back gracefully

---

## Requirements

- Neovim **0.9+**
- *(optional)* [lib.nvim](https://github.com/stefanbartl/lib.nvim) — for enhanced notifications, keymaps, and git helpers

---

## Installation

**lazy.nvim**
```lua
{
  "stefanbartl/sessions.nvim",
  dependencies = { "stefanbartl/lib.nvim" }, -- optional
  opts = {},
}
```

**pckr / packer**
```lua
use {
  "stefanbartl/sessions.nvim",
  requires = { "stefanbartl/lib.nvim" }, -- optional
  config = function()
    require("sessions").setup()
  end,
}
```

---

## Configuration

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

  -- Auto-save the contextual session on VimLeavePre.
  autosave = true,

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

  -- Normal-mode keymaps. Set individual keys to false to disable them,
  -- or set the whole table to false to disable all keymaps.
  keymaps = {
    save    = "<leader>ssa",
    load    = "<leader>slo",
    save_ts = "<leader>sst",
    list    = "<leader>sli",
  },
})
```

---

## Commands

| Command | Description |
|---|---|
| `:SessionSave [name]` | Save session (auto-named if omitted) |
| `:SessionSaveTimestamp` | Save with a `sess-YYYYMMDD-HHMMSS` suffix |
| `:SessionLoad [name]` | Load session (tab-completes saved names) |
| `:SessionDelete <name>` | Delete session + companion metadata |
| `:SessionRename <old> <new>` | Rename session + companion metadata |
| `:SessionList` | List sessions with timestamp and branch |
| `:SessionCurrent` | Print the active session name |
| `:SessionToggleTrack [name]` | Toggle `git skip-worktree` on a session file |

---

## Keymaps

Default Normal-mode keymaps:

| Key | Action |
|---|---|
| `<leader>ssa` | `:SessionSave` |
| `<leader>slo` | `:SessionLoad` |
| `<leader>sst` | `:SessionSaveTimestamp` |
| `<leader>sli` | `:SessionList` |

Disable all: `keymaps = false`

---

## Public API

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

**Statusline example**
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

---

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

---

## Metadata

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

Used by `:SessionList` for timestamps and branch display. Access it in Lua:
```lua
local meta = require("sessions").metadata("myapp_feature-login")
-- meta.saved_at, meta.branch, meta.buffers, ...
```

---

## Git Integration

`:SessionToggleTrack` solves the cross-device sync dilemma:

- You want named sessions (e.g. `myapp_main`) committed to your config repo
  so they sync to other machines.
- You do **not** want `last.vim` committed because its absolute paths only
  exist on the current machine and cause errors on others.

**Setup:**
```lua
require("sessions").setup({
  root = vim.fn.stdpath("config") .. "/sessions",
})
```

Run `:SessionToggleTrack last` once to mark `last.vim` as skip-worktree.
The file stays on disk, but git ignores changes to it. Run again to un-skip.

---

## Health Check

```vim
:checkhealth sessions
```

Reports Neovim version compatibility, optional dependency status, active
configuration, session root accessibility, session count, and command
registration.
