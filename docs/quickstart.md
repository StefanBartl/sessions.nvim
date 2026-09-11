# Quick Start

**Save a session**
```bash
nvim my-file.lua          # work on files...
# :Session save           # inside Neovim, or just exit and let autosave do it
```

**Restore the session**
```bash
# Wherever you left off (project + branch aware) — no quoting, own command:
nvim +LastSession

# The same resolution, spelled as a :Session subcommand — needs quoting:
nvim '+Session load'

# Explicit session name — needs quoting:
nvim '+Session load myntest'
nvim '+Session load myapp_feature-login'
```

> `:Session` is one command with subcommands (`load`, `save`, …), built via
> `lib.nvim.bindings.usercmd.composer`. A bare Neovim CLI `+cmd` flag is one shell
> word, so any invocation with a space — `Session load`, `Session load
> <name>` — needs to be quoted as a single argument. `:LastSession` is a
> plain, separate, single-word command specifically so the single most common
> case (restore wherever you left off) doesn't need quoting — it resolves
> exactly like a bare `:Session load` (see docs/configuration.md's "Session
> Naming"), not a hardcoded name.

## Workflow example (with autosave enabled)

Autosave and branch/project-aware naming are both on by default, so there's
nothing to configure — this is only here to show it explicitly:
```lua
require("sessions").setup({
  autosave = true,
  autosave_name = true, -- resolve by branch/project, like a bare :Session save
})
```

Then use it:
```bash
nvim src/main.lua        # work, then exit (autosaved under this project/branch's name)
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
