# Commands

One command, `:Session <subcommand>` (built via
[`lib.nvim.bindings.usercmd.composer`](https://github.com/StefanBartl/lib.nvim), with
`<Tab>` completion — session-name args complete dynamically), plus a
standalone `:LastSession` convenience command.

| Command | Description |
|---|---|
| `:Session save [name]` | Save session (auto-named if omitted) |
| `:Session save-timestamp` | Save with a `sess-YYYYMMDD-HHMMSS` suffix |
| `:Session load [name]` | Load session (tab-completes saved names); omitted name prefers the current project/branch's own session, else the remembered last-loaded one, else `default_name` |
| `:Session delete <name>` | Delete session + companion metadata |
| `:Session rename <old> <new>` | Rename session + companion metadata |
| `:Session list` | List sessions with timestamp and branch |
| `:Session stale` | List saved sessions whose recorded branch no longer exists (read-only) — see [Stale sessions](#stale-sessions) below |
| `:Session delete-stale` | Delete every session `:Session stale` would list, after one confirm for the whole batch |
| `:Session current` | Print the active session name |
| `:Session toggle-track [name]` | Toggle `git skip-worktree` on a session file |
| `:Session save-tab [name]` | Save only the current tab's window layout (stored separately from full sessions) |
| `:Session load-tab <name>` | Load a tab session into a new tab, leaving other tabs untouched |
| `:Session save-layout <name>` | Save the current window-split structure only (no buffers/files) |
| `:Session load-layout <name>` | Restore a window-split layout onto whatever buffers are currently open |
| `:LastSession` | Load wherever you left off — same resolution as a bare `:Session load`, unquoted-CLI-friendly (`nvim +LastSession`) |
| `:SessionLoad` | Open a session picker with live preview (Snacks.picker or Telescope) — see [Picker Integration](picker.md) |
| `:Session marks …` | The mark list — an ordered set of files jumped to by number, with pins and defaults; `add`, `remove`, `pin`, `unpin`, `defaults sync\|reset`, `select <n>`, `preview <n>`, `menu [kind]`, `list`, `debug`, `import-harpoon`. Off unless `marks.enable = true`; see [Marks](marks.md) |

## Stale sessions

A session saved with `branch_aware`/`project_aware` on records the branch
and `cwd` it was saved from. Over time some of those branches stop
existing — merged and deleted, most often a removed Claude Code worktree
branch — while their session file just sits there forever, since nothing
ever tells you which ones are still good.

`:Session stale` re-checks every such session's recorded branch against
the repository at its recorded `cwd` and lists the ones that no longer
resolve — read-only, same shape as `:Session list`. A session with no
recorded branch (a custom name, or saved with both `*_aware` options off)
is never a candidate; there is nothing to re-check it against. Nor is a
session whose lookup itself can't be answered either way (the directory
and its repo both check out, but the branch listing itself failed) —
ambiguous is deliberately never treated as confirmed-stale.

`:Session delete-stale` runs the same check and deletes what it finds,
after **one** confirm for the whole batch (not once per session). Nothing
here runs automatically (e.g. on `VimLeavePre`): a branch that is merely
checked out somewhere else right now, not currently open in this editor,
must never get swept just because it isn't the *cwd*'s current branch —
staleness here specifically means "this branch is gone", not "you are on
a different one right now".

## Keymaps

Keymaps are **disabled by default**. Enable them in your setup:

```lua
require("sessions").setup({
  keymaps = {
    save    = "<leader>ssa",
    load    = "<leader>slo",
    save_ts = "<leader>sst",
    list    = "<leader>sli",
  },
})
```

Or disable individual keymaps:
```lua
keymaps = {
  save = "<leader>ssa",
  load = false,  -- disabled
  -- ...
}
```
