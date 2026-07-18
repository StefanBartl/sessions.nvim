# Quick Start

**Save a session**
```bash
nvim my-file.lua          # work on files...
# :SessionSave            # inside Neovim, or just exit and let autosave do it
```

**Restore the session**
```bash
# Auto-resolved (project + branch aware):
nvim +SessionLoad

# Explicit session name:
nvim +SessionLoad last
nvim +SessionLoad myntest
nvim +SessionLoad myapp_feature-login
```

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
nvim +SessionLoad        # restore the workspace
```

Switch branches and restore the right session:
```bash
# Session auto-named by branch: "myapp_main"
git checkout main
nvim +SessionLoad        # loads "myapp_main" (auto-resolved)

# Switch to feature branch: "myapp_feature-auth"
git checkout feature-auth
nvim +SessionLoad        # loads "myapp_feature-auth"
```

**Requirements for `nvim +SessionLoad`:**
Must use `lazy = false` in your plugin spec (see [Installation](installation.md)).
