```
  ███████╗███████╗███████╗███████╗██╗ ██████╗ ███╗   ██╗███████╗
  ██╔════╝██╔════╝██╔════╝██╔════╝██║██╔═══██╗████╗  ██║██╔════╝
  ███████╗█████╗  ███████╗███████╗██║██║   ██║██╔██╗ ██║███████╗
  ╚════██║██╔══╝  ╚════██║╚════██║██║██║   ██║██║╚██╗██║╚════██║
  ███████║███████╗███████║███████║██║╚██████╔╝██║ ╚████║███████║
  ╚══════╝╚══════╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝
                                               .nvim
```

[![Neovim](https://img.shields.io/badge/Neovim-0.9+-57A143?logo=neovim&logoColor=white)](https://neovim.io)

> 💡 Pairs well with [dap.nvim](https://github.com/StefanBartl/dap.nvim) and
> [language.nvim](https://github.com/StefanBartl/language.nvim): sessions.nvim
> restores your workspace by project + branch, so your debug configs and
> spell/translate settings pick up right where you left off.

Branch- and project-aware Neovim sessions — no external dependencies beyond
the built-in `:mksession` / `:source`.

---

## Quick Start

```lua
-- lazy.nvim
{
  "stefanbartl/sessions.nvim",
  dependencies = { "stefanbartl/lib.nvim" }, -- required
  event = "VimEnter",
  opts = {},
}
```

```bash
nvim my-file.lua          # work on files...
# :Session save           # inside Neovim, or just exit and let autosave do it

nvim '+Session load'      # restore the workspace (auto-resolved by project + branch)
nvim +LastSession         # or: load the fixed "last" session — no quoting needed
```

See [Installation](docs/installation.md) and [Quick Start](docs/quickstart.md) for details, including the `nvim '+Session load'` startup requirements and why it needs quoting.

---

## Documentation

- [Installation](docs/installation.md) — requirements and plugin manager setup (lazy.nvim, pckr/packer).
- [Quick Start](docs/quickstart.md) — saving, restoring, and branch-aware workflow examples.
- [Configuration](docs/configuration.md) — all available setup options, defaults, and session naming rules.
- [Commands](docs/commands.md) — the full `:Session <subcommand>` reference and keymap setup.
- [Public API](docs/api.md) — the Lua API (`require("sessions")`) and a statusline example.
- [Metadata](docs/metadata.md) — the `.{name}.json` companion file format and how to read it.
- [Git Integration](docs/git-integration.md) — syncing named sessions across machines with `:Session toggle-track`.
- [Portability](docs/portability.md) — `relative_paths` and `root_remap` for sessions synced across machines/OSes.
- [Session Scoping](docs/session-scoping.md) — tab-scoped sessions and window-layout-only snapshots.
- [Picker Integration](docs/picker.md) — `:SessionLoad` via Snacks.picker or Telescope, with preview and multi-select delete.
- [Troubleshooting](docs/troubleshooting.md) — using `:checkhealth sessions` to diagnose setup issues.
- [Roadmap](docs/ROADMAP.md) — planned features and future direction.
- [Bindings](docs/BINDINGS.md) — every keymap and user command.

---

## Features

- **Branch-aware** — session name automatically includes the current git branch, so switching branches restores a different workspace
- **Project-aware** — detects your project root (`.git`, `package.json`, …) and prefixes the session name
- **Metadata** — a companion `.json` records the save timestamp, branch, and buffer list for statuslines or pickers
- **`sessions.statusline`** — ready-made `component()` for lualine/heirline: session name + dirty indicator when the layout has changed since the last save
- **Clean save** — blacklisted buffer types, filetypes, and path prefixes are wiped before `:mksession` (no quickfix noise, no temp files)
- **E445 fix** — modified buffers are hidden (not discarded) before loading, so the session's internal `only`/`tabonly` never triggers E445
- **`:Session delete` / `:Session rename`** — lifecycle commands missing from most session plugins
- **`:Session toggle-track`** — toggle `git skip-worktree` on a session file to sync named sessions via your config repo without committing transient state
- **`:checkhealth sessions`** — self-diagnostic for setup verification
- **`autoload = "ask"`** — floating y/n prompt before restoring on startup; the remembered last-loaded session survives restarts even without it
- **`relative_paths` / `root_remap`** — portable sessions that re-anchor to wherever they're loaded, or translate absolute path prefixes across machines/OSes
- **`:Session save-tab` / `load-tab`** — save/restore just the current tab's windows, independent of the rest of your tabs
- **`:Session save-layout` / `load-layout`** — reapply a favorite split arrangement to whatever's currently open, without touching buffers
- **`:SessionLoad`** — session picker with live preview and multi-select delete, via Snacks.picker or Telescope (neither is a hard dependency)
- **`lib.nvim`** — required for the `:Session`/`:LastSession` commands themselves; `lib.nvim.notify`, `lib.nvim.map`, and `lib.nvim.git` stay soft-guarded and fall back gracefully if those specific submodules aren't resolvable
