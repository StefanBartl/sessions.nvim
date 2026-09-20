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

Branch- and project-aware Neovim sessions. The session name resolves from the
project root and the current git branch, so switching branches restores a
different workspace and you never have to name anything. Built on Neovim's own
`:mksession` and `:source`, not around them. Optionally also a mark list —
files jumped to by number, with pins and remembered cursor positions — for
the handful of files you want one keypress away in every project.

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
> **[ui.nvim](https://github.com/StefanBartl/ui.nvim)** — renders this
> plugin's own `sessions.statusline` component in its statusline, so the
> active session is visible without asking for it. This plugin owns the
> text; ui.nvim only places it.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real
> dependency — see [Requirements](docs/installation.md#requirements).

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

### The Basics

- [Requirements](docs/installation.md#requirements) — Neovim version, required plugins and CLI tools.
- [Installation](docs/installation.md) — a spec per plugin manager.
- [Quickstart](docs/quickstart.md) — the shortest path: save a session, load it back, including the `nvim '+Session load'` startup requirements and why it needs quoting.

### Configuration

- [What you get with the defaults](docs/what-you-get.md) — the full command surface at a glance.
- [All options](docs/configuration.md) — every option, its default, and the session naming rules.
- [Command reference](docs/commands.md) — `:Session <subcommand>`, subcommand by subcommand.
- [Bindings](docs/BINDINGS.md) — every keymap, user command and autocommand. The keys are off by default, so this is also where you learn what to switch on.

### The Rest

- [Features](docs/FEATURES.md) — everything this plugin does, in one file.
- [Picker](docs/picker.md) — `:SessionLoad`, its live preview and multi-select delete.
- [Marks](docs/marks.md) — the opt-in mark list: files jumped to by number, pins and defaults, its own promptless list+preview UI, and taking over a harpoon list. Concept inspired by [ThePrimeagen's harpoon.nvim](https://github.com/ThePrimeagen/harpoon) — thanks!
- [Session scoping](docs/session-scoping.md) — two lighter alternatives to a full session, for when a whole one is more than you want.
- [Workflow](docs/WORKFLOW.md) — how sessions, branches and scoping combine over a working day.
- [Statusline](docs/statusline.md) — the ready-made component, what its dirty marker means, and why it is cheap enough for a hotpath.
- [Git integration](docs/git-integration.md) — what `:Session toggle-track` is for: the cross-device sync dilemma, and which side of it you are choosing.
- [Portability](docs/portability.md) — why `:mksession` is already half portable, and what has to be done about the other half.
- [Metadata](docs/metadata.md) — what the hidden `.{name}.json` holds, and what it buys.
- [Lua API](docs/api.md) — every function a config or another plugin can call.
- [Troubleshooting](docs/troubleshooting.md) — using `:checkhealth sessions` to diagnose a setup.
- [Contributing](docs/CONTRIBUTING.md) — ground rules, project layout, and where a change belongs.
- [Feedback](https://github.com/StefanBartl/sessions.nvim/issues) — bugs, feature requests and usage questions; broader discussion in [Discussions](https://github.com/StefanBartl/sessions.nvim/discussions).

`:help sessions` is the same reference inside the editor.

---

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

sessions.nvim is released under the [MIT License](https://opensource.org/licenses/MIT).
