# sessions.nvim — module map

> **Generated** by `documentation`. Do not edit by hand — run `:DocMap`
> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.

**6 modules** · 2 namespaces · 10 helper files

The [interactive map](index.html) has filtering, full descriptions and
source links; this page is the version the code host renders directly.


## Namespaces

```mermaid
flowchart LR
  nlua["sessions.nvim"]
  nlua_sessions["sessionsbr/smallMinimal usage: require('sessions').setup()/small"]
  nlua_sessions_bindings["bindings"]
  nlua_sessions_config["configbr/smallHolds and merges the active…/small"]
  nlua --> nlua_sessions
  nlua_sessions --> nlua_sessions_bindings
  nlua_sessions --> nlua_sessions_config
```


## Dependencies

Which parts of the tree require which, rolled up to the second level.
The [interactive map](index.html)'s **Deps** view has this per module,
in both directions, with load-time and lazy requires told apart.

```mermaid
flowchart LR
  nlua_sessions_bindings["bindings"]
  nlua_sessions_config["sessions.config"]
  nlua_sessions_core_lua["sessions.core"]
  nlua_sessions_git_lua["sessions.git"]
  nlua_sessions_health_lua["sessions.health"]
  nlua_sessions_layout_lua["sessions.layout"]
  nlua_sessions_meta_lua["sessions.meta"]
  nlua_sessions_picker_lua["sessions.picker"]
  nlua_sessions_portable_lua["sessions.portable"]
  nlua_sessions_state_lua["sessions.state"]
  nlua_sessions_statusline_lua["sessions.statusline"]
  nlua_sessions_bindings --> nlua_sessions_config
  nlua_sessions_bindings --> nlua_sessions_core_lua
  nlua_sessions_bindings --> nlua_sessions_layout_lua
  nlua_sessions_bindings --> nlua_sessions_picker_lua
  nlua_sessions_core_lua --> nlua_sessions_config
  nlua_sessions_core_lua --> nlua_sessions_git_lua
  nlua_sessions_core_lua --> nlua_sessions_meta_lua
  nlua_sessions_core_lua --> nlua_sessions_portable_lua
  nlua_sessions_core_lua --> nlua_sessions_state_lua
  nlua_sessions_health_lua --> nlua_sessions_bindings
  nlua_sessions_health_lua --> nlua_sessions_config
  nlua_sessions_health_lua --> nlua_sessions_core_lua
  nlua_sessions_layout_lua --> nlua_sessions_config
  nlua_sessions_picker_lua --> nlua_sessions_core_lua
  nlua_sessions_statusline_lua --> nlua_sessions_core_lua
```


## Modules

| Module | Description | Fns | Docs |
|---|---|---|---|
| `sessions` | Minimal usage: require("sessions").setup() | 9 | [src](../../lua/sessions/init.lua) |
| &nbsp;&nbsp;`bindings` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`sessions.bindings.autocmds` | Also wires the structural dirty-tracking autocmds (BufAdd/BufDelete/...) that back `sessions.core.mark_dirty()` for the statusline component. | 4 | [src](../../lua/sessions/bindings/autocmds/init.lua) |
| &nbsp;&nbsp;&nbsp;&nbsp;`sessions.bindings.keymaps` | Disabled unless `setup({ keymaps = { ... | 1 | [src](../../lua/sessions/bindings/keymaps/init.lua) |
| &nbsp;&nbsp;&nbsp;&nbsp;`sessions.bindings.usercmds` | Registers :Session <subcommand>, one verb built via lib.nvim's composer (:Verb sub … + <Tab> completion + Markdown docgen), plus a standalone :LastSession… | 7 | [src](../../lua/sessions/bindings/usercmds/init.lua) |
| &nbsp;&nbsp;&nbsp;&nbsp;`sessions.bindings.which_key` | which-key is a **soft** dependency: if it is not installed this is a no-op. | 2 | [src](../../lua/sessions/bindings/which_key/init.lua) |
| &nbsp;&nbsp;`sessions.config` | Holds and merges the active `Sessions.Config`, applied by `M.setup()` on top of `sessions.config.DEFAULTS`. | 2 | [src](../../lua/sessions/config/init.lua) |

## Drift

1 errors · 1 warnings · 9 info

| Severity | Check | Message |
|---|---|---|
| error | `module-path-mismatch` | lua/sessions/config/DEFAULTS.lua declares @module 'sessions.DEFAULTS' but lives at 'sessions.config.DEFAULTS' |
| warn | `require-not-declared` | requires "sessions.config.DEFAULTS" (line 11), which no file in this tree declares |

<details>
<summary>9 informational findings</summary>


| Check | Message |
|---|---|
| `missing-readme` | lua/sessions has no README.md |
| `missing-readme` | lua/sessions/bindings/autocmds has no README.md |
| `missing-readme` | lua/sessions/bindings/keymaps has no README.md |
| `missing-readme` | lua/sessions/bindings/usercmds has no README.md |
| `missing-readme` | lua/sessions/bindings/which_key has no README.md |
| `missing-readme` | lua/sessions/config has no README.md |
| `unreferenced-module` | sessions.DEFAULTS is required by no other file in the tree |
| `unreferenced-module` | sessions.health is required by no other file in the tree |
| `unreferenced-module` | sessions.statusline is required by no other file in the tree |

</details>
