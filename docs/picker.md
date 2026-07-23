# Picker Integration

`:SessionLoad` opens a session picker with live preview — backed by
[Snacks.picker](https://github.com/folke/snacks.nvim) if available,
otherwise [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).
Neither is a hard dependency: if you have neither installed, `:SessionLoad`
just prints an error telling you so; every other `:Session` command works
without them.

```vim
:SessionLoad
```

Or from Lua: `require("sessions").pick()`.

- The currently active session is marked with `*` in the list.
- The preview pane shows the buffer list, save timestamp, branch, and cwd
  from the session's [metadata](metadata.md) (blank if `metadata = false`).
- `<CR>` loads the selected session.
- `<C-d>` deletes the selection — multi-select first (`<Tab>` in
  Telescope; check your Snacks.picker multi-select mapping) to delete
  several sessions at once.

Which backend is used is decided automatically: Snacks first, then
Telescope. There's no config option to pick one over the other — install
just the one you want if that matters to you.
