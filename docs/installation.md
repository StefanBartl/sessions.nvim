# Installation

## Requirements

- Neovim **0.9+**
- *(optional)* [lib.nvim](https://github.com/stefanbartl/lib.nvim) — for enhanced notifications, keymaps, and git helpers

## lazy.nvim

*Default (lazy-loaded on command use):*
```lua
{
  "stefanbartl/sessions.nvim",
  dependencies = { "stefanbartl/lib.nvim" }, -- optional
  cmd = { "SessionSave", "SessionLoad", "SessionDelete", "SessionRename", "SessionList", "SessionCurrent", "SessionToggleTrack" },
  opts = {},
}
```

*Load after UI init (recommended for autoload/autosave):*
```lua
{
  "stefanbartl/sessions.nvim",
  dependencies = { "stefanbartl/lib.nvim" }, -- optional
  event = "VimEnter",
  opts = {},
}
```

*Load at startup (for `nvim +SessionLoad` command-line args):*
```lua
{
  "stefanbartl/sessions.nvim",
  dependencies = { "stefanbartl/lib.nvim" }, -- optional
  lazy = false,
  opts = {},
}
```

## pckr / packer

*Default setup:*
```lua
use {
  "stefanbartl/sessions.nvim",
  requires = { "stefanbartl/lib.nvim" }, -- optional
  config = function()
    require("sessions").setup()
  end,
}
```

*With immediate load (packer equivalent of `lazy = false`):*
```lua
use {
  "stefanbartl/sessions.nvim",
  requires = { "stefanbartl/lib.nvim" },
  module_pattern = "sessions", -- eager
  config = function()
    require("sessions").setup()
  end,
}
```

## When to use which

| Variant | Startup impact | Commands via `:Cmd` | Commands via `nvim +Cmd` | When to use |
|---|---|---|---|---|
| **`cmd` (lazy)** | Minimal | ✓ (loads on use) | ✗ | Large config, many plugins |
| **`event = "VimEnter"`** | Minimal (after UI) | ✓ (loads at VimEnter) | ✗ | **Recommended** — autoload/autosave timing |
| **`lazy = false`** | High (immediate) | ✓ | ✓ | Want `nvim +SessionLoad` to work, or instant command availability |

**Note:** Command-line args like `nvim +SessionLoad` execute **before** lazy-loading hooks, so you need `lazy = false` for those to work. For all other use cases, `cmd` or `event = "VimEnter"` is recommended.
