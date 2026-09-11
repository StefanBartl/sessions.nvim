# Workflow — using sessions.nvim day to day

Every feature here is documented on its own in `docs/FEATURES.md`. This is
the different question: how saving, loading, and the branch-aware naming
actually combine once you stop thinking about them and just switch
branches or projects.

## The steady-state loop needs nothing from you

With the defaults (`autosave = true`, `autosave_name = true`,
`branch_aware = true`, `project_aware = true`), the entire day-to-day
workflow is: open Neovim, work, quit. `VimLeavePre` autosaves to the same
branch/project-aware name a bare `:Session save` would use (`autosave_name
= true` resolves it that way — see docs/configuration.md), and
`nvim +LastSession` restores it next time — no `:Session save` needed
unless you want a *named* session to come back to deliberately (a
milestone, a specific investigation) rather than just "wherever I left
off".

## `nvim +LastSession` and `nvim '+Session load'` are the same resolution now

Both need `lazy = false` (or another eager-load trigger active at startup)
in the plugin spec, or the CLI `+cmd` flag fires before the plugin is even
loaded and does nothing. Beyond that, pick whichever reads better in a
shell alias — `+LastSession` needs no quoting, `'+Session load'` does — the
two now resolve identically: the current project/branch's own session
first (if it has been saved at least once), else the remembered
last-loaded/saved session, else `default_name`. `:Session load <name>`
stays the way to load something else on purpose.

This used to be a real trap: `+LastSession` hardcoded the literal `"last"`
autosave slot, so `+LastSession` after a `git checkout` could restore
whatever was open when you last quit *on any branch*, not the workspace
tied to the branch you just switched to. Both the resolution `:LastSession`
uses and the default `autosave_name` changed together to close that gap —
see docs/configuration.md's "Session Naming" for the exact priority order.
If you explicitly set `autosave_name` to a fixed string (the old default),
that trap is back by design: autosave always targets that one name again,
so `+LastSession`/bare `:Session load` will prefer it over any
branch-aware session that happens to exist too.

## Branch switches restore a different workspace — that's the point, not a bug

`branch_aware = true` means `myapp_main` and `myapp_feature-login` are
genuinely different sessions with different buffer lists. A `git checkout`
mid-session does **not** auto-reload anything — sessions.nvim only resolves
names at save/load time, it has no branch-change hook. The combo that
actually gets you branch-switching behavior is manual:

```vim
:Session save          " snapshot current branch's workspace before switching
:!git checkout other-branch
:Session load           " auto-resolves to other-branch's own session
```

Skipping the first `:Session save` before switching is worse than it looks
with the default `autosave_name = true`: `VimLeavePre` still autosaves on
exit, and by then `git` reports the *new* branch — so the old branch's
still-open buffers get saved **into the new branch's own session file**,
overwriting whatever was genuinely saved there. (With a fixed
`autosave_name` string it was merely imprecise — everything landed in one
shared slot instead. Auto-resolving made a skipped save actively
destructive to the target branch's session, not just uninformative.)

## Metadata `branch` only populates when you opted into git

`docs/metadata.md`'s `branch` field, and the `:SessionLoad` preview / picker
`*` marker that lean on it, stay empty unless `branch_aware` or
`project_aware` is enabled — `sessions.git` is lazy-loaded and never shells
out to `git` otherwise. If you disabled both because you don't want the
auto-naming behavior but still want branch info in `:Session list`/the
picker preview, there's no way to get one without the other today.

## Portability: `relative_paths` re-anchors on load, `root_remap` doesn't touch what's already relative

These solve different halves of the same cross-machine problem and can be
used together. `relative_paths` handles everything inside `cwd` (the
common case, since `:mksession`'s own `curdir` option already makes most
buffer paths cwd-relative) — it only needs the *loading* machine to `cd`
into the right project directory first. `root_remap` is for paths that
stay absolute regardless (outside `cwd`, or `relative_paths` left off) and
needs the exact old-root → new-root prefix spelled out per machine pair.
The trap: `root_remap` rewrites on an in-memory copy every load, so it's
safe to keep entries for machines you're not currently on — but
`relative_paths`' rewrite happens once, at *save* time, into the stored
`.vim` file itself. A session saved with `relative_paths = false` and later
switched to `true` in config does not retroactively become portable; only
sessions saved after the config change get the placeholder treatment.

## `:Session toggle-track` is a one-time setup step, not a per-save action

Run `:Session toggle-track <name>` once per session you want synced via a
dotfiles/config repo (`root` pointed at a path inside that repo) — it
flips git's `skip-worktree` bit and stays flipped across every future save
of that session file. The trap: forgetting to toggle whatever autosave
writes to (`"last.vim"` with a fixed `autosave_name`; the current
branch/project's own file with the default `autosave_name = true`) *off*
of tracking — or never toggling it on in the first place — means a
machine-local autosave session gets committed and immediately breaks on
every other machine's absolute paths (unless `relative_paths` is also on).
Named, deliberately-saved sessions are what this feature is for; an
autosave session almost never is.

## Every mappable subcommand has a keymap option now — including the ones you had to type

The keymap table was a hardcoded four while `:Session` had grown to twelve
subcommands, so `toggle-track`, `save-tab`, `load-tab`, `save-layout` and
`load-layout` had no option at all. All eleven mappable ones plus
`:SessionLoad` are configurable now, and the original four keep their names
(`save_ts` still spells `save-timestamp`) so an existing config does not break
quietly.

**`delete` and `rename` stay out, and the reason is not that they are
destructive.** `:Session save` overwrites just as readily and is mappable. They
take a **required argument**, and a keymap is a bare keypress with nothing to
pass. Configuring one now says exactly that, instead of "Unknown
keymaps.delete" — which would send you hunting for a spelling mistake that is
not there.

which-key needs no change: it walks whatever is configured and computes the
group prefix from that.

## Tab and layout snapshots don't participate in the main session lifecycle

`save-tab`/`load-tab` and `save-layout`/`load-layout` are stored in their
own directories (`root/.tabs/`, `root/layouts/`) specifically so they don't
show up in `:Session list`, aren't touched by `metadata`, and don't update
the remembered last-loaded session. Don't expect `:Session list` or the
`:SessionLoad` picker to surface a tab/layout snapshot you saved earlier —
there's no unified picker across all three session kinds; tab and layout
names have to be remembered separately (or looked up on disk under those
two subdirectories).
