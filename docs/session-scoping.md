# Session Scoping

Two lighter-weight alternatives to a full session, for when you don't want
to save/restore your entire workspace.

## Tab-scoped sessions

`:Session save-tab [name]` saves only the *current tab's* window layout —
other tabs are ignored entirely. Stored separately from full sessions,
under `root/.tabs/`, so they never collide with (or show up in) `:Session
list`.

```vim
:Session save-tab feature-review
:Session load-tab feature-review
```

`:Session load-tab <name>` opens a **new tab** and restores the snapshot
into it, leaving every other open tab untouched — unlike `:Session load`,
which collapses to a single tab.

Auto-naming, `relative_paths`, and `root_remap` all apply the same way
they do to full sessions; `metadata`, hooks' `on_save`/`on_load` (still
fires), and the remembered last-loaded state do not (those track the full
workspace session, not tab snapshots).

## Window-layout snapshots

`:Session save-layout <name>` captures just the *split structure* of the
current tab — the row/column arrangement and window sizes — not which
files or buffers are open.

```vim
:Session save-layout three-pane
:Session load-layout three-pane
```

`:Session load-layout <name>` reconstructs that split structure against
whatever buffer(s) are currently open in the tab, the way a manual
`:vsplit`/`:split` would. Useful for reapplying a favorite pane
arrangement (e.g. "editor + two terminals") to a fresh file, independent
of any specific session.

Stored as JSON under `root/layouts/`, separate from both full sessions and
tab sessions.
