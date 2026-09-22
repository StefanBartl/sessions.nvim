# Troubleshooting

## Health Check

```vim
:checkhealth sessions
```

Reports Neovim version compatibility, optional dependency status, active
configuration, session root accessibility, session count, and command
registration.

## My tabline (NvChad tabufline) order resets after loading a session

Expected before `restore_buffer_order` existed: `:mksession` cannot store a
tab-local variable, and NvChad's tabufline keeps its order in `vim.t.bufs`.
sessions.nvim now persists that list in a `.{name}.bufs.json` sidecar and
reapplies it on load (`opts.restore_buffer_order`, default `true`).

If the order still resets:

- The buffer paths must match. A session saved with `relative_paths` or
  `root_remap` that resolves buffers to **different absolute paths** than at
  save time will not re-match them — the buffers still load, just in
  `:mksession` order.
- The sidecar lives next to the `.vim` file (`root/.<name>.bufs.json`). If
  you sync sessions between machines, sync the dotfiles too.
- It only acts on tabpages that have a `vim.t.bufs` when the session
  finishes sourcing. If your tabline plugin builds that list lazily on a
  later event, the reorder may need a `:redrawtabline` (or just a buffer
  switch) to show.

## A buffer shows up blank in the tabline after loading a session

Fixed: this happened when a file that was open in a saved session got
deleted or moved outside Neovim before the session was loaded again.
`:mksession` writes a listed buffer as `edit <path>`/`badd <path>`
regardless of whether that path still exists, so sourcing it just opened a
new, empty buffer under the old name and left it sitting in the layout.

sessions.nvim now checks every listed buffer's backing file both when
saving (so a session is never written pointing at a file that is already
gone) and right after loading (so a buffer resurrected from a
since-deleted path is wiped instead of left blank). A modified buffer is
never touched by this, even if its file is missing, so in-memory unsaved
content is never discarded. Dropped paths are reported by `:Session save`
and `:Session load` as `dropped (file no longer exists): ...`.
