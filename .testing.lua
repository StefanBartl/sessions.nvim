-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "sessions",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "h",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next). Needed: init_spec runs setup(), a one-shot, and
  -- statusline_spec expects no active session; the old run.lua guaranteed that by file order.
  isolated = "file",
  -- Environment variables the specs read; a child editor inherits an allowlist only (never secrets).
  env_allow = { "LIB_NVIM_DIR" },
  -- Guards (docs/GUARDS.md of testing.nvim). Measured on this suite: the only finding is the file-system
  -- guard seeing the fixtures below; state, scheduled errors, prompts and deprecations are clean, so
  -- they raise instead of warn. The process/network guard is measured too.
  guards = {
    fs = "error",
    state = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    process_net = "error",
  },
  -- What the guards let through on purpose.
  guard_allow = {
    -- Every spec keeps its session store in a TESTS/.fixture-* directory that it creates and removes.
    fs = { "TESTS" },
    -- The branch/repo specs make throwaway git repositories (git init, symbolic-ref, rev-parse).
    spawn = { "git" },
  },
}
