# Quick Start

**Save a session**
```bash
nvim my-file.lua          # work on files...
# :Session save           # inside Neovim, or just exit and let autosave do it
```

**Restore the session**
```bash
# Auto-resolved (project + branch aware) — needs quoting, it's two words:
nvim '+Session load'

# The fixed "last" session — no quoting needed, this is its own command:
nvim +LastSession

# Explicit session name — needs quoting:
nvim '+Session load myntest'
nvim '+Session load myapp_feature-login'
```

> `:Session` is one command with subcommands (`load`, `save`, …), built via
> `lib.nvim.usercmd.composer`. A bare Neovim CLI `+cmd` flag is one shell
> word, so any invocation with a space — `Session load`, `Session load
> <name>` — needs to be quoted as a single argument. `:LastSession` is a
> plain, separate, single-word command specifically so the single most common
> case (restore the last session) doesn't need quoting.

## Workflow example (with autosave enabled)

First, make sure autosave is enabled (it should be default) in your setup:
```lua
require("sessions").setup({
  autosave = true,
  autosave_name = "last",
})
```

Then use it:
```bash
nvim src/main.lua        # work, then exit (auto-saved to "last")
nvim +LastSession        # restore the workspace
```

Switch branches and restore the right session:
```bash
# Session auto-named by branch: "myapp_main"
git checkout main
nvim '+Session load'        # loads "myapp_main" (auto-resolved)

# Switch to feature branch: "myapp_feature-auth"
git checkout feature-auth
nvim '+Session load'        # loads "myapp_feature-auth"
```

**Requirements for `nvim +LastSession` / `nvim '+Session load ...'`:**
Must use `lazy = false` in your plugin spec (see [Installation](installation.md)).
