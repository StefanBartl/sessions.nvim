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

## "could not write the ... sidecar" after a save

Next to each session file sessions.nvim keeps hidden sidecars:
`.<name>.json` (metadata), `.<name>.bufs.json` (tabline buffer order) and
`.<name>.pins.json` (pinned buffers). The session file itself is written
first, so the save still succeeds when a sidecar cannot be written, but the
metadata, order or pins of that save are lost. Earlier this happened
silently; now each failed sidecar is reported as a warning naming the file
and the reason.

The usual cause on Windows is a path of 260 characters or more while long
paths are not enabled (the warning then says so and gives the length). Pick
a shorter `root`, or enable long paths for the system
(`LongPathsEnabled`). Other causes are the usual ones: no write permission
in `root`, a full disk, or a directory sitting where the file should be.
