# TESTS/

Headless spec suite, run by [testing.nvim](https://github.com/StefanBartl/testing.nvim).
No plugin manager, no picker, no real session on disk except the fixtures the
specs write themselves.

```
bash scripts/test.sh                 # every spec
bash scripts/test.sh --file config   # only spec files whose name contains "config"
bash scripts/test.sh --json ir.json  # also write the machine-readable result
```

Exit 0 is a pass; one line per spec file, exit 1 on a failure *or* when nvim,
testing.nvim or lib.nvim cannot be found (the error names all four places that
were searched). CI runs exactly this script. The configuration is
[`.testing.lua`](../.testing.lua): dialect `h` (the specs run on
`TESTS/harness.lua`), one nvim per spec file.

## Dependencies

testing.nvim and lib.nvim (`sessions.portable` and several other modules
require it at module load) are resolved by `scripts/test.sh`, each in this
order:

1. `$TESTING_NVIM_DIR` / `$LIB_NVIM_DIR`
2. `.deps/<name>` (what CI could check out)
3. a sibling checkout, `../<name>`
4. the plugin-manager copy under `stdpath("data")/lazy/<name>`

A sibling wins over the plugin-manager copy on purpose: that one is often older
than the working checkout, and testing against a stale lib.nvim gives
misleading failures.


## No network, no subprocesses

Nothing in this suite spawns a process or touches the network, and that is not
an accident of the fixtures — every place the plugin could reach outside itself
is cut at a seam that is replaced in `package.loaded` *before* the module under
test requires it:

| Seam | Replaced in | Instead of |
| --- | --- | --- |
| `lib.nvim.git`, `lib.nvim.fs.find_upward_dir` | `git_spec` | asking lib.nvim about a real checkout |
| `sessions.git` | `core_spec`, `autocmds_spec` | resolving a name from whichever checkout the suite runs in |
| `vim.system`, `lib.nvim.cross.run_argv` | `usercmds_spec` | two real `git update-index` spawns |
| `snacks`, `telescope*` | `picker_spec`, `init_spec` | a picker backend that is neither installed nor needed |
| `ui.kit` | `autocmds_spec` | ui.nvim, which is not a dependency here |
| `lib.nvim.notify`, `vim.notify`, `vim.health` | several | writing into the user's messages/health output |

The "repositories" in `git_spec` are directories with a `.git` written by hand,
which is all the process-free branch resolution ever reads.

## The specs

| | |
| --- | --- |
| `sanitize_spec.lua` | the whitelist that turns a branch or directory name into a filename — the one place where a path separator or a `..` must not survive |
| `resolve_name_spec.lua` | which parts make up an automatic session name, and that a usable name always comes back |
| `git_spec.lua` | where the branch and the project root come from: lib.nvim when installed, and the process-free `.git/HEAD` / upward-search fallback when not — worktree `.git` files, detached HEAD and garbage HEAD included |
| `config_spec.lua` | the merge, and that `DEFAULTS` survives it unmutated |
| `state_spec.lua` | `.state.json`, the one pointer that remembers which session to resume, including what a corrupt one reads as |
| `meta_spec.lua` | the sidecar file's round-trip and its rename/delete lifecycle |
| `buforder_spec.lua` | the `vim.t.bufs` ordering sidecar, and that `core` writes and reapplies it at the right moments |
| `portable_spec.lua` | the placeholder rewrite, and that loading never mutates the stored file |
| `layout_spec.lua` | window-split snapshots: capture, restore, list, delete, and what a corrupt layout file does |
| `statusline_spec.lua` | what the component renders with and without a session, the dirty marker, and that it does not mutate the caller's options |
| `core_spec.lua` | the whole save/load/list/delete/rename surface, the blacklist, both name-resolution rules, hooks, `relative_paths`, and tab sessions |
| `picker_spec.lua` | what `:SessionLoad` hands a backend and what its actions do: item list, preview text, delete bookkeeping, and the fallback chain when nothing is installed |
| `health_spec.lua` | the `:checkhealth` report, per dependency present and absent |
| `keymaps_spec.lua` | the opt-in mappings: what is declared vs. bound, the unmappable names, and the computed which-key prefix |
| `usercmds_spec.lua` | every `:Session` subcommand, `:LastSession`, `:SessionLoad` and the completion types — driven through real `:` commands |
| `autocmds_spec.lua` | the VimEnter autoload, the VimLeavePre autosave and the dirty-tracking events, fired with `nvim_exec_autocmds` |
| `init_spec.lua` | `setup()` — including that it is a one-shot — and the public API on `sessions` |

Adding one: write `TESTS/<name>_spec.lua` returning `function(H) ... end`.
It is discovered by its `_spec.lua` suffix. `H` is the harness — `eq`, `ok`, `falsy`, `contains`,
`excludes`, `read` (a file back as one string), `fixture` (a scratch directory
plus its cleanup function), `stub` (replace a module, or make it look
uninstalled, and get a restore function back) and `fresh` (re-require a module
so it re-resolves its soft dependencies against the stubs in place right now).

Every spec file runs in its own nvim (`isolated = "file"` in `.testing.lua`),
so no order matters: `statusline_spec` asserts what the component renders with
*no* session loaded, and `init_spec` calls `setup()`, a one-shot that registers
the real commands, autocmds and keymaps. The old `run.lua` guaranteed that by
file order; one process per file guarantees it without.

## A note on fixtures

`H.fixture()` creates its directory inside the repository rather than in
`vim.fn.tempname()`. On Windows the temp path carries an 8.3 short component
(`STEFAN~1`) that several Vim path builtins do not see through, so a
tempname-based fixture would pass on Linux and quietly assert nothing here.

The path is anchored at `TESTS/` itself rather than at `getcwd()`: `git_spec`
moves the working directory to resolve a branch from somewhere else, and a
cwd-relative fixture would then be created — and cleaned up — in the wrong
place.

## Coverage

Every module under `lua/sessions/` has a spec, except the ones listed below.
Each spec drives the real thing wherever that is possible: real session files
written by `:mksession` and sourced back, real windows and tabpages, real user
commands invoked as `:` commands, real autocmds fired with
`nvim_exec_autocmds`, real buffer-local keymaps answered with real keystrokes.

Deliberately not covered:

- `lua/sessions/@types/init.lua` — annotations only, no runtime code.
- `lua/sessions/config/DEFAULTS.lua` — a declarative table. Its values are
  asserted indirectly by every spec that relies on a default, and its one piece
  of logic (the per-OS blacklist paths) is covered by `config_spec`.
- The *rendering* half of both picker backends. Everything on this side of the
  boundary is covered against stubs — the items, the preview text, the format
  callback, the confirm and delete actions, the reopen-after-delete — but
  actually drawing a picker window needs snacks.nvim or telescope.nvim, and
  neither is a dependency of this plugin nor a CI checkout.
- `health.lua`'s trailing `composer.checkhealth("Session")` call, when it
  actually runs: it reports on lib.nvim's own verb registry, which lib.nvim
  tests there. The *guard* around that call — that it does not run at all
  when `lib.nvim.bindings.usercmd.composer` failed to load — is covered in
  `health_spec.lua` (see bug 3 below).

## Three bugs found here, now fixed

All three were first pinned in their broken shape with a `BUG:` comment; all
three are **fixed**, and the assertions stayed on as regression guards.

1. **`core.save`/`core.save_tab` used to raise instead of reporting.** `M.save`
   promises `(boolean ok, string|nil path_or_err)` and every caller renders the
   second value as "save failed: …". The `:mksession` call was `pcall`ed
   accordingly, but the `ensure_dir()` above it was not — so a root that cannot
   be created (a file in the way, a read-only volume, a path component that is
   itself a file) escaped as a raw `E739: Cannot create directory`, including
   out of the `VimLeavePre` autosave, where it surfaced while Neovim was
   quitting. `ensure_dir` now returns `(ok, err)` and both callers report it
   through the same contract as every other failure. Pinned in `core_spec.lua`.
2. **`layout.restore` used to raise on valid JSON that is not a layout
   tree.** The guard was `type(tree) ~= "table"`, which only rejects JSON that
   does not decode at all; `{}`, `[]` or anything else table-shaped passed it,
   and `build()` then took the length of a nil child list — "attempt to get
   length of a nil value" instead of the "corrupt or missing layout file" the
   same function promises one line above. `restore` now walks the decoded tree
   with a recursive `is_valid_node` check before ever calling `build()`, so a
   malformed node fails the same way however deep it hides. Pinned in
   `layout_spec.lua`.
3. **`health.lua`'s report used to crash instead of degrading when
   `lib.nvim.bindings.usercmd.composer` failed to load.** The preflight check
   a few lines up (`pcall(require, "lib.nvim.bindings.usercmd.composer")`)
   already reports that as `vim.health.error(...)`, but the trailing
   `composer.checkhealth("Session")` call at the end of `M.check()` ran
   unconditionally — `require`ing straight back into a module that had
   already failed to load re-raises ("loop or previous error loading
   module"), turning the *diagnostic* command itself into an uncaught error
   instead of the warning already on screen. Every other spec in this suite
   runs with lib.nvim as a hard dependency (see above), so this was the one
   branch nothing ever exercised. `M.check()` now guards the call with the
   same `lib_composer_ok` the preflight check already computed. Pinned in
   `health_spec.lua`.

One further quirk is pinned as behaviour rather than as a defect
(`core_spec.lua`): `core.rename` does not update `.state.json`, so between
renaming the active session and the next save, a bare `:Session load` and
autoload look for a name that no longer exists and fall back to `default_name`.
