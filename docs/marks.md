# Marks

An ordered list of files you keep coming back to, jumped to by number, with
the cursor position remembered per file. `:Session marks` opens it, `:Session
marks add` puts the current file on it, `<leader>3` (once you bind it) opens
the third entry where you left it.

This is what harpoon's list is, built into the plugin that already owns
"where was I" — and in one respect it is the opposite of a session: a
session is *this project's* workspace, while the mark list, by default, is
the same everywhere. A cheatsheet, a notes file and your config's plugin
spec are the files you want one keypress away regardless of which repository
you are in.

The list itself, the jump-by-number keymaps and the harpoon import below are
a straight take on [ThePrimeagen's harpoon.nvim](https://github.com/ThePrimeagen/harpoon)
— thanks for the idea. The `kit` menu (see below) is this plugin's own UI
for it, built for the same "a handful of files, not a haystack" shape.

Off by default. Turn it on with `marks = { enable = true }`.

## The three kinds of entry

| | Comes from | Lives in | Survives `defaults reset` |
| --- | --- | --- | --- |
| **mark** | `:Session marks add`, the edit menu, a harpoon import | the scope's store | no |
| **default** | `marks.defaults` in your config | the config, so every machine | yes |
| **pin** | `:Session marks pin` at runtime | `root/marks/pins.json`, this machine only | yes |

A default or pin is still an ordinary line in the list — reorder it, delete
it — but the edit menu flags it (`📌 pin` at end of line) and asks before it
drops out, and `:Session marks defaults sync` brings it back. Delete a plain
mark and it is simply gone.

`marks.defaults` takes path *specs*: a list of segments whose first may be
`$REPOS_DIR`, `$HOME` or `$NVIM_HOME` (the config directory), or one absolute
string. A spec whose variable is unset resolves to nothing and is skipped —
so a work-only path in a shared config costs nothing at home.

```lua
marks = {
  enable = true,
  defaults = {
    { "$NVIM_HOME", "lua", "plugins", "personal", "init.lua" },
    { "$REPOS_DIR", "Notes", "spickzettel.md" },
    "/absolute/path/also/fine.md",
  },
}
```

## Scope

`marks.scope = "global"` (default): one list, one store
(`root/marks/global.json`), wherever Neovim runs.

`marks.scope = "project"`: one list per project root — the same detection
sessions use — and per branch when `branch_aware` is on. The store is
`root/marks/<project>-<hash>[-<branch>].json`. Pins are shared across scopes
either way; they are a property of the machine, not of a project.

## Commands

| Command | Does |
| --- | --- |
| `:Session marks` | Open the list in the configured picker (`marks.menu.ui`) |
| `:Session marks menu [auto\|edit\|kit\|snacks\|telescope\|fzf]` | Open it in a specific UI |
| `:Session marks add [path] [--front] [--permanent]` | Add (current buffer if no path); `--front` puts it first, `--permanent` also pins it |
| `:Session marks remove [path]` | Drop from the list |
| `:Session marks pin [path] [--front]` | Pin, and add if not listed |
| `:Session marks unpin [path]` | Stop treating it as a default; the list entry stays |
| `:Session marks defaults sync` | Append every default and pin that is missing |
| `:Session marks defaults reset` | The list becomes exactly the defaults and pins, in that order |
| `:Session marks select <n>` | Jump to entry `n`, cursor where it was |
| `:Session marks preview <n>` | Read-only float of entry `n`; `q` closes |
| `:Session marks list` | Print the list |
| `:Session marks debug` | Scope, store path and list in a scratch buffer |
| `:Session marks import-harpoon [bucket]` | Take over a harpoon v2 list (see below) |

A path argument tab-completes as a file. Every one of these answers with a
single line when `marks.enable` is off, rather than "unknown subcommand".

## The menus

**`edit`** is the one that changes the list: a floating buffer, one absolute
path per line. Reorder lines, delete some, paste a new one — `:w` or closing
the window (`q`, `<Esc>`, or just leaving it) hands the lines back and the
list follows. `<CR>` on a line opens that file; `<C-x>`, `<C-v>`, `<C-t>`
open it in a split, vsplit or tab. Deleting a line that is a default or pin
asks: *list only* (it returns on the next `defaults sync`), *unpin too*, or
*keep it*.

**`kit`** is this plugin's own UI (built on `ui.nvim`'s `ui.kit.shortlist`),
tried first by `auto`: no fuzzy-search prompt — this list rarely holds more
than a handful of entries, so there is nothing to search through — and the
preview sits *above* the list instead of beside it, both full width, so a
path label gets more room than a picker's narrow results column would leave.
Pinned entries carry the same `📌 pin` marker as the edit menu, and
`<C-x>`/`<C-v>`/`<C-t>` open a split, vsplit or tab. Needs `ui.nvim`
installed; falls back to `edit` if it is not.

**`snacks`**, **`telescope`** and **`fzf`** show the same list with shortened
labels (`C:/…/parent/file.ext`), preview the file, and open an entry with the
same `<C-x>`/`<C-v>`/`<C-t>` variants. `auto` — the default — tries `kit`
first, then the first of these installed, and falls back to `edit`, which
needs nothing at all.

## Keymaps

Eight named actions join the `keymaps` table when marks are on, all opt-in
like the rest:

| Config key | Runs |
| --- | --- |
| `marks_menu` | `:Session marks` |
| `marks_edit` | `:Session marks menu edit` |
| `marks_add` | `:Session marks add` |
| `marks_add_front` | `:Session marks add --front` |
| `marks_pin` | `:Session marks pin --front` |
| `marks_remove` | `:Session marks remove` |
| `marks_sync` | `:Session marks defaults sync` |
| `marks_debug` | `:Session marks debug` |

The numbered jumps are templates with one `%d`, expanded for 1 to 9:

```lua
marks = {
  enable = true,
  select_key = "<leader>%d",   -- <leader>1 … <leader>9 jump
  preview_key = "<M-%d>",      -- <M-1> … <M-9> preview
},
```

## Cursor positions

Leaving a buffer whose file is on the list records the cursor position
(debounced by `marks.context_debounce_ms`, 200 ms by default, so a burst of
window switches is one write). `select`, the pickers and the preview put the
cursor back there. A position past the end of a file that got shorter is
clamped, never an error.

## Coming from harpoon

With `marks.import_harpoon = true` (the default), the first time the store
for a scope is created the plugin looks for a harpoon v2 data file holding a
bucket keyed by `stdpath("config")` — the key a single-global-list harpoon
setup uses — and takes its entries, in harpoon's order and with harpoon's
cursor positions, before topping up with the defaults. Without one, the
defaults alone are seeded. Either way this happens once: the marker file
`root/marks/.seeded-<scope>` records it, and an emptied list stays empty.

`:Session marks import-harpoon [bucket]` does the same on demand, merging
harpoon's entries ahead of whatever is already listed. The bucket argument is
for a per-directory harpoon setup, where the key is the directory.

Harpoon itself is never touched, read-only included: the two can run side by
side while you decide.
