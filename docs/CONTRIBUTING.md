# Contributing to sessions.nvim

Thank you for your interest! Bugs, ideas and questions are welcome in the
[issue tracker](https://github.com/StefanBartl/sessions.nvim/issues); pull
requests very welcome.

## Getting the repository into a session

Clone it and either symlink the checkout into your plugin directory or add it
to the runtime path directly:

```lua
vim.opt.rtp:prepend("/path/to/sessions.nvim")
require("sessions").setup({})
```

[lib.nvim](https://github.com/StefanBartl/lib.nvim) has to be on the runtime
path too — the `:Session` and `:LastSession` commands are built on it.

Work on a throwaway session directory while developing. A bug in the save path
writes over the session you were actually using, and that is exactly the kind
of mistake this plugin exists to prevent.

## Ground rules

- Lua only, idiomatic Neovim Lua. 2-space indentation, `stylua.toml` decides
  the rest.
- **Build on `:mksession`, do not replace it.** Neovim's own session format is
  the substrate; everything here decides *which* session, cleans up what goes
  into it, and adds what the format cannot carry. A hand-rolled serializer for
  something `:mksession` already writes is the wrong direction.
- **Never lose a buffer.** Modified buffers are *hidden* before a load, not
  discarded — that is why the session's own `only` / `tabonly` does not trigger
  E445. Any new path that touches windows or buffers has to preserve that.
- **Deletion is explicit.** `delete` and `rename` act on a named session and
  say what they removed, including the metadata and buffer-order sidecars. No
  operation cleans up "stale" sessions on its own.
- **A sidecar is optional by construction.** The metadata `.json` and the
  buffer-order file add information the session format cannot carry, and a
  session with neither must still load. A reader that assumes a sidecar exists
  is a bug.
- **`lib.nvim` submodules stay soft.** The command layer needs lib.nvim, but
  `lib.nvim.notify`, `lib.nvim.bindings.keymap` and `lib.nvim.git` are guarded
  and fall back. Keep new uses in that shape.
- **Keymaps are off by default.** The plugin registers commands and
  autocommands; keys are opt-in, and [`BINDINGS.md`](BINDINGS.md) is where a
  user finds out what to switch on.
- **The statusline component is a hotpath.** It is called on every redraw. Two
  table lookups and a memoized options merge — see
  [`statusline.md`](statusline.md) — and nothing that shells out, walks a
  directory, or allocates per call.
- Descriptive commit messages.

## Project layout

| Path | Contains |
| --- | --- |
| `lua/sessions/core.lua` | Save, load, the active-session state and the dirty flag |
| `lua/sessions/state.lua` | What survives across restarts, including the remembered last session |
| `lua/sessions/git.lua` | Branch resolution, and `toggle-track`'s `skip-worktree` handling |
| `lua/sessions/meta.lua` | The `.{name}.json` sidecar |
| `lua/sessions/buforder.lua` | The `vim.t.bufs` ordering sidecar `:mksession` cannot carry |
| `lua/sessions/portable.lua` | `relative_paths` and `root_remap` |
| `lua/sessions/layout.lua` | Tab-scoped sessions and layout-only snapshots |
| `lua/sessions/picker.lua` | `:SessionLoad`, over snacks.picker or telescope |
| `lua/sessions/statusline.lua` | The ready-made component |
| `lua/sessions/bindings/` | `usercmds/`, `keymaps/`, `autocmds/` — the last of which is what marks a session dirty |
| `lua/sessions/config/` | `DEFAULTS.lua` and validation |
| `doc/`, `docs/` | The vimdoc, and everything the README links to |
| `TESTS/` | The spec suite |

## Adding a subcommand

1. Put the logic in the module that owns that concern — `core`, `layout`,
   `portable`, `git` — and keep the command layer to argument parsing and
   rendering.
2. Route it in `lua/sessions/bindings/usercmds/`, with completion over session
   names where that makes sense.
3. If it writes anything beside the `.vim` file, it is a sidecar: optional to
   read, cleaned up by `delete` and moved by `rename`. Check both.
4. If it changes windows or buffers, hide rather than discard — see the ground
   rules.
5. Add a spec under `TESTS/`.
6. Document it in [`commands.md`](commands.md), [`BINDINGS.md`](BINDINGS.md)
   and [`FEATURES.md`](FEATURES.md).

## Tests

`TESTS/` is a headless spec suite over name resolution, the sanitizer, the
metadata and buffer-order sidecars, portability and the statusline component.

```
nvim --headless -u NONE -c "set rtp+=." -l TESTS/run.lua
```

Exit 0 is a pass. [GitHub Actions](../.github/workflows/ci.yml) runs it plus
stylua and luacheck on every push and pull request to `main`.

Specs work against fixture directories rather than a real session directory,
for the reason in the setup section above.

## Workflow

1. Fork the repository.
2. Branch as `feature/<name>`.
3. Make the change, add a spec, update the affected pages under `docs/`.
4. Open a PR with a clear description of what changed and why.
