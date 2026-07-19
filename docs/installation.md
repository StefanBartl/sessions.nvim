# Installation

## Requirements

- Neovim **0.9+**
- [lib.nvim](https://github.com/stefanbartl/lib.nvim) — **required**: the `:Session`/`:LastSession` commands are built on `lib.nvim.usercmd.composer`. `lib.nvim.notify`, `lib.nvim.map`, and `lib.nvim.git` stay soft-guarded (used when available, native fallback otherwise).

## lazy.nvim

*Default (lazy-loaded on command use):*
```lua
{
  "stefanbartl/sessions.nvim",
  dependencies = { "stefanbartl/lib.nvim" },
  cmd = { "Session", "LastSession" },
  opts = {},
}
```

*Load after UI init (recommended for autoload/autosave):*
```lua
{
  "stefanbartl/sessions.nvim",
  dependencies = { "stefanbartl/lib.nvim" },
  event = "VimEnter",
  opts = {},
}
```

*Load at startup (for `nvim +LastSession` / `nvim '+Session load'` command-line args):*
```lua
{
  "stefanbartl/sessions.nvim",
  dependencies = { "stefanbartl/lib.nvim" },
  lazy = false,
  opts = {},
}
```

## pckr / packer

*Default setup:*
```lua
use {
  "stefanbartl/sessions.nvim",
  requires = { "stefanbartl/lib.nvim" },
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

| Variant | Startup impact | Commands via `:Session ...` | Commands via `nvim +Cmd` | When to use |
|---|---|---|---|---|
| **`cmd` (lazy)** | Minimal | ✓ (loads on use) | ✗ | Large config, many plugins |
| **`event = "VimEnter"`** | Minimal (after UI) | ✓ (loads at VimEnter) | ✗ | **Recommended** — autoload/autosave timing |
| **`lazy = false`** | High (immediate) | ✓ | ✓ | Want `nvim +LastSession` / `nvim '+Session load'` to work, or instant command availability |

**Note:** Command-line args like `nvim +LastSession` execute **before** lazy-loading hooks, so you need `lazy = false` for those to work. For all other use cases, `cmd` or `event = "VimEnter"` is recommended. `:Session` is a single command with subcommands (`load`, `save`, …) built via `lib.nvim.usercmd.composer` — a multi-word CLI invocation like `nvim +Session load` needs to be quoted as one shell argument (`nvim '+Session load'`), since Neovim's `+cmd` flag is a single word by default. `:LastSession` is a separate, single-word command specifically so the most common case (restore the last session) doesn't need quoting.
