# Statusline

`require("sessions.statusline").component(opts?)` returns a ready-made string:
the active session name, with a dirty marker appended when the window and
buffer layout has changed since the last save or load — that is, what the next
autosave would capture. It returns `""` when no session is active.

It is a plain Lua string with no hard dependency on any statusline plugin, and
it is safe to call unconditionally on every redraw.

## Options

```lua
---@class Sessions.StatuslineOpts
---@field icon?       string  Prefix before the session name (default "")
---@field dirty_icon? string  Suffix when the layout changed since the last save (default " *")
---@field empty?      string  Returned when no session is active (default "")
```

## Wiring it up

### lualine

```lua
require("lualine").setup({
  sections = {
    lualine_c = {
      function() return require("sessions.statusline").component() end,
    },
  },
})
```

### heirline

```lua
{ provider = function() return require("sessions.statusline").component({ icon = " " }) end }
```

### The native statusline

```vim
set statusline+=%{v:lua.require('sessions.statusline').component()}
```

## What "dirty" means here

The marker is not about unsaved *buffers* — Neovim already tells you about
those. It is about the **session** being out of date: a buffer added or
deleted, a window or tab opened or closed, since the session was last written.

Structural autocommands registered in `sessions.bindings.autocmds` set the flag
through `sessions.core.mark_dirty()`, and it is cleared on the next save or
load. So the marker answers one question: would exiting right now lose part of
this layout?

There is deliberately no timer and no polling. The flag changes when the
structure changes, and a statusline redraw only reads a boolean.

## Why it is cheap

`component()` is a hotpath — a statusline plugin calls it on every redraw,
potentially many times a second while you type or move the cursor.

The merged options table is memoized per distinct `opts` table rather than
being rebuilt on every call. lualine and heirline pass the same table reference
each redraw, so the merge happens once. The cache is weak-keyed, so an entry
disappears as soon as the caller's own table is collected — passing a fresh
table literal on every redraw still works, it just gives up the memoization.

Everything else the component does is two table lookups: the current session
name and the dirty flag, both already in memory.

## Beyond the component

If you want something the component does not render — the save timestamp, the
branch, the buffer list — that is in the session's metadata sidecar rather than
here. `require("sessions").metadata(name)` returns it, and
[metadata.md](metadata.md) says what it holds and when it is written.
