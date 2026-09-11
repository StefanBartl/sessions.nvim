> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# sessions.nvim

```
  ███████╗███████╗███████╗███████╗██╗ ██████╗ ███╗   ██╗███████╗
  ██╔════╝██╔════╝██╔════╝██╔════╝██║██╔═══██╗████╗  ██║██╔════╝
  ███████╗█████╗  ███████╗███████╗██║██║   ██║██╔██╗ ██║███████╗
  ╚════██║██╔══╝  ╚════██║╚════██║██║██║   ██║██║╚██╗██║╚════██║
  ███████║███████╗███████║███████║██║╚██████╔╝██║ ╚████║███████║
  ╚══════╝╚══════╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
                                                          .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
[![CI](https://github.com/StefanBartl/sessions.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/sessions.nvim/actions/workflows/ci.yml)

Branch- and project-aware Neovim sessions.

The session name resolves from the project root and the current git branch, so
switching branches restores a different workspace and you never have to name
anything. Built on Neovim's own `:mksession` and `:source`, not around them.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Statusline](#statusline)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

- [Features](docs/FEATURES.md) — everything this plugin does, in one file.
- [Installation](docs/installation.md) — requirements, and a spec per plugin manager.
- [Quickstart](docs/quickstart.md) — the shortest path: save a session, load it back, including the `nvim '+Session load'` startup requirements and why it needs quoting.
- [Configuration](docs/configuration.md) — every option, its default, and the session naming rules.
- [Command reference](docs/commands.md) — `:Session <subcommand>`, subcommand by subcommand.
- [Bindings](docs/BINDINGS.md) — every keymap, user command and autocommand. The keys are off by default, so this is also where you learn what to switch on.
- [Picker](docs/picker.md) — `:SessionLoad`, its live preview and multi-select delete.
- [Session scoping](docs/session-scoping.md) — two lighter alternatives to a full session, for when a whole one is more than you want.
- [Workflow](docs/WORKFLOW.md) — how sessions, branches and scoping combine over a working day.
- [Statusline](docs/statusline.md) — the ready-made component, what its dirty marker means, and why it is cheap enough for a hotpath.
- [Git integration](docs/git-integration.md) — what `:Session toggle-track` is for: the cross-device sync dilemma, and which side of it you are choosing.
- [Portability](docs/portability.md) — why `:mksession` is already half portable, and what has to be done about the other half.
- [Metadata](docs/metadata.md) — what the hidden `.{name}.json` holds, and what it buys.
- [Lua API](docs/api.md) — every function a config or another plugin can call.
- [Troubleshooting](docs/troubleshooting.md) — using `:checkhealth sessions` to diagnose a setup.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and where a change belongs.

`:help sessions` is the same reference inside the editor.

---

## What it does

Neovim can already save a session. What it cannot do is decide *which* one:
`:mksession` writes wherever you point it, and every workflow built on it ends
up as a naming convention held together by hand. This plugin makes the name a
function of where you are.

| Area | Does |
| --- | --- |
| **Naming** | The project root — `.git`, `package.json`, and the rest — plus the current git branch. Switch branches and a different workspace comes back |
| **Lifecycle** | `save`, `load`, `delete` and `rename`, the last two missing from most session plugins, plus autosave on exit and an `autoload = "ask"` prompt on start |
| **Clean saves** | Blacklisted buffer types, filetypes and path prefixes are wiped before `:mksession` — no quickfix noise, no temp files in tomorrow's session |
| **Portability** | `relative_paths` re-anchors a session wherever it is loaded, and `root_remap` translates absolute prefixes across machines and operating systems |
| **Scoping** | `save-tab` / `load-tab` for one tab's windows, and `save-layout` / `load-layout` to reapply a split arrangement to whatever is already open |
| **Metadata** | A companion `.json` recording the save timestamp, branch and buffer list, for a picker or a statusline to read without sourcing anything |
| **Sync** | `:Session toggle-track` flips `git skip-worktree` on a session file, so named sessions travel through your config repo without committing transient state |

Two details that exist because the obvious implementation gets them wrong:
modified buffers are **hidden rather than discarded** before a load, so the
session's own `only` / `tabonly` never triggers E445; and NvChad tabufline's
`vim.t.bufs` ordering — which `:mksession` cannot carry — is persisted in a
sidecar and reapplied, a no-op if you do not use such a tabline.

---

## Around it

> **[dap.nvim](https://github.com/StefanBartl/dap.nvim)** — debug
> configurations that pick up where you left them, because the workspace they
> belong to came back.
>
> **[language.nvim](https://github.com/StefanBartl/language.nvim)** — the same
> for a spell session and its target language.
>
> **[pickers.nvim](https://github.com/StefanBartl/pickers.nvim)** — the other
> way into a project: jump to the repository, and let this plugin restore what
> you were doing in it.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real
> dependency — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.9+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — the `:Session` and `:LastSession` commands themselves are built on it |

`lib.nvim.notify`, `lib.nvim.bindings.keymap` and `lib.nvim.git` are
soft-guarded on top of that: if one of those submodules does not resolve, the
plugin falls back rather than failing.

Optional, each detected at runtime and degrading to nothing when absent:

| | |
| --- | --- |
| `git` | Branch-aware session names. Without it the project part still works |
| [snacks.nvim](https://github.com/folke/snacks.nvim) or telescope.nvim | `:SessionLoad`, the picker with live preview and multi-select delete |
| A tabufline | The `vim.t.bufs` ordering sidecar, a no-op without one |

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/sessions.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  event = "VimEnter",
  opts = {},
}
```

`event = "VimEnter"` rather than a command trigger: autoload and the autosave
autocommands have to be in place before you do anything, not after you first
type `:Session`. pckr and packer specs are in
[docs/installation.md](docs/installation.md).

---

## Quickstart

Work as usual, then let it save on exit — or say so explicitly:

```vim
:Session save
```

Coming back, from the shell:

```bash
nvim '+Session load'      # restore the workspace, auto-resolved by project + branch
nvim +LastSession         # the same resolution — no quoting needed
```

The quoting in the first form is not optional, and
[docs/quickstart.md](docs/quickstart.md) says why, along with what has to be
true at startup for a session to restore cleanly.

Verify your setup any time with:

```vim
:checkhealth sessions
```

---

## What you get with the defaults

| Command | Does |
| --- | --- |
| `:Session save` / `load` | Save or restore, auto-resolved by project and branch |
| `:Session delete` / `rename` | The lifecycle commands most session plugins leave out |
| `:LastSession` | Wherever you left off — project/branch-aware, remembered across restarts |
| `:SessionLoad` | The picker: live preview, multi-select delete |
| `:Session save-tab` / `load-tab` | Just the current tab's windows, independent of the rest |
| `:Session save-layout` / `load-layout` | Reapply a split arrangement to whatever is open, without touching buffers |
| `:Session toggle-track` | Flip `git skip-worktree` on a session file, for syncing named sessions |

Keymaps are off by default — [docs/BINDINGS.md](docs/BINDINGS.md) is both the
inventory and the list of what to switch on. Every option, including
`autoload = "ask"` for the y/n prompt on startup, is
[docs/configuration.md](docs/configuration.md).

---

## Statusline

`require("sessions.statusline").component()` returns the active session name
with a dirty marker when the layout has changed since the last save — that is,
when exiting now would lose part of it. It returns `""` with no session active,
has no hard dependency on any statusline plugin, and is cheap enough to call on
every redraw. See [docs/statusline.md](docs/statusline.md) for the options and
the lualine, heirline and native wiring.

---

## Health check

```vim
:checkhealth sessions
```

Four sections: the environment, lib.nvim and which of its submodules resolved,
the configuration as it was merged, and the registered commands.
[docs/troubleshooting.md](docs/troubleshooting.md) reads the common symptoms
back to which of those four answers them.

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) has the ground rules and the
project layout.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/sessions.nvim/issues) to report
bugs, suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/sessions.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
