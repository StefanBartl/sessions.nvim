# TESTS/

Headless spec suite. No plugin manager, no picker, no real session on disk
except the fixtures the specs write themselves.

```
nvim --headless -u NONE -c "set rtp+=." -l TESTS/run.lua
```

Exit 0 is a pass; the runner prints one line per spec and exits non-zero on the
first failure. CI runs exactly this command.

## lib.nvim

`sessions.portable` and several other modules require lib.nvim at module load,
so the suite cannot run without it. `run.lua` resolves it in this order:

1. `$LIB_NVIM_PATH`
2. a sibling checkout, `../lib.nvim`
3. the lazy.nvim-managed copy under `stdpath("data")/lazy/lib.nvim`

A sibling wins over the plugin-manager copy on purpose: that one is often older
than the working checkout, and testing against a stale lib.nvim gives
misleading failures.

## The specs

| | |
| --- | --- |
| `sanitize_spec.lua` | the whitelist that turns a branch or directory name into a filename — the one place where a path separator or a `..` must not survive |
| `resolve_name_spec.lua` | which parts make up an automatic session name, and that a usable name always comes back |
| `config_spec.lua` | the merge, and that `DEFAULTS` survives it unmutated |
| `meta_spec.lua` | the sidecar file's round-trip and its rename/delete lifecycle |
| `portable_spec.lua` | the placeholder rewrite, and that loading never mutates the stored file |
| `statusline_spec.lua` | what the component renders with no session, and that it does not mutate the caller's options |

Adding one: write `TESTS/<name>_spec.lua` returning `function(H) ... end`, then
list it in `run.lua`. `H` is the harness — `eq`, `ok`, `falsy`, `contains`,
`excludes`, `read` (a file back as one string) and `fixture` (a scratch
directory plus its cleanup function).

## A note on fixtures

`H.fixture()` creates its directory inside the repository rather than in
`vim.fn.tempname()`. On Windows the temp path carries an 8.3 short component
(`STEFAN~1`) that several Vim path builtins do not see through, so a
tempname-based fixture would pass on Linux and quietly assert nothing here.
