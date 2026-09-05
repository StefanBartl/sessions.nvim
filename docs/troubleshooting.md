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
