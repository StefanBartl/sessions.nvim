---@module 'sessions.git'
---@brief Git helpers for branch/project-aware session naming.
---@description
--- Prefers lib.nvim when available; falls back to direct vim.fn calls.

---@class SessionsGit
local M = {}

---@internal
---Find the `.git` entry for `start_path` (searching upward), resolving a
---worktree/submodule's `.git` FILE ("gitdir: <path>") down to the real git
---directory. Purely filesystem-based -- no process spawn, so nothing here
---can fail because the `git` *binary* itself is unavailable, refused
---(`safe.directory`), or slow (a stale network mount): those failure modes
---are exactly what made a `git`-spawning version of this check unable to
---tell "genuinely no repo here" apart from "the command itself failed" --
---see `M.branch_exists()`'s own doc comment for why that distinction
---matters enough to have rewritten it around this instead of `lib.nvim.git`.
---@param start_path string
---@return string|nil  # the real git directory, or nil if none was found/resolvable
local function find_gitdir(start_path)
  local found = vim.fs.find(".git", { path = start_path, upward = true, limit = 1 })
  if not (found and found[1]) then
    return nil
  end

  local dotgit = found[1]
  local uv = vim.uv or vim.loop
  local stat = uv.fs_stat(dotgit)
  if not stat then
    return nil
  end

  if stat.type == "file" then
    -- Worktree/submodule: .git is a file holding "gitdir: <path>".
    local ok_lines, gl = pcall(vim.fn.readfile, dotgit, "", 1)
    local gitdir = ok_lines and gl and gl[1] and gl[1]:match("^gitdir:%s*(.+)$")
    if not gitdir then
      return nil
    end
    if not gitdir:match("^[/\\]") and not gitdir:match("^%a:") then
      gitdir = vim.fs.dirname(dotgit) .. "/" .. gitdir
    end
    dotgit = gitdir
  end

  return dotgit
end

---@internal
---`.git/HEAD` carries the same information a `git symbolic-ref --short
---HEAD` subprocess would: "ref: refs/heads/<branch>" on a branch, a raw
---SHA when detached (in which case there is no branch name and nil is
---correct). Shared by `M.current_branch()`'s own no-`lib.nvim.git`
---fallback and `M.current_branch_no_spawn()` below.
---@param start_path string
---@return string|nil
local function read_branch_from_head(start_path)
  local dotgit = find_gitdir(start_path)
  if not dotgit then
    return nil
  end

  local ok_head, head = pcall(vim.fn.readfile, dotgit .. "/HEAD", "", 1)
  if not ok_head or not head or not head[1] then
    return nil
  end

  local branch = head[1]:match("^ref:%s*refs/heads/(.+)$")
  return (branch and branch ~= "") and vim.trim(branch) or nil
end

---@return string|nil
function M.current_branch()
  local ok, git = pcall(require, "lib.nvim.git")
  if ok then
    local branch = git.current_branch()
    -- Guard against lib.nvim returning error-like strings
    return (branch and branch ~= "" and not branch:lower():find("error")) and branch or nil
  end
  -- Fallback without spawning a process -- `lib.nvim.git` isn't installed,
  -- so this is the only way to answer at all. Runs on every session name
  -- resolution, which is the whole reason a process spawn had to go.
  return read_branch_from_head(vim.fn.getcwd())
end

--- Same question as `M.current_branch()`, but NEVER through
--- `lib.nvim.git` -- always the direct `.git/HEAD` read, even when
--- `lib.nvim.git` is installed and `current_branch()` above would prefer
--- it. For a caller on a much higher-frequency path than session-name
--- resolution (`sessions.chip_text`'s "modern" text, re-read on every
--- `ui.kit.chip` refresh -- an editing-rate event, BufAdd/BufDelete/
--- WinNew/WinClosed/TabNewEntered/TabClosed), where `current_branch()`'s
--- own default of *preferring* a real `git` subprocess would be a real,
--- measurable cost: `lib.nvim`'s own docs call that runner "by a wide
--- margin, the biggest source of UI freezes" across the plugins built on
--- it. The direct file read is the same mechanism `current_branch()`'s
--- own fallback already trusts as correct whenever `lib.nvim.git` isn't
--- around at all -- just used unconditionally here instead of only when
--- there is no other option.
---@return string|nil
function M.current_branch_no_spawn()
  return read_branch_from_head(vim.fn.getcwd())
end

---@param markers string[]
---@return string|nil
function M.project_root(markers)
  local ok, find_upward = pcall(require, "lib.nvim.fs.find_upward_dir")
  if ok then
    local root = find_upward(markers, vim.fn.getcwd())
    -- Guard against lib.nvim returning error-like strings
    if root and root ~= "" and not root:lower():find("error") then
      return root
    end
    return nil
  end
  -- Fallback: vim.fs.find (Neovim built-in)
  local found = vim.fs.find(markers, { path = vim.fn.getcwd(), upward = true })
  if found and found[1] then
    local dir = vim.fs.dirname(found[1])
    if dir and dir ~= "" then
      return dir
    end
  end
  return nil
end

--- Whether `branch` still exists as a local branch in the repo recorded at
--- `cwd`. Used to detect a stale session (`:Session stale`/`delete-stale`):
--- its own recorded `cwd`/`branch` no longer add up to a real, checkoutable
--- branch, most often because the worktree that `cwd` pointed at was
--- removed after its branch got merged.
---
--- Deliberately filesystem-only (`find_gitdir()` + a loose/packed ref read),
--- never `lib.nvim.git`/a `git` subprocess -- an earlier version of this
--- went through `lib.nvim.git.in_git_repo()`/`.refs()`, on the theory that a
--- raised Lua error from those would signal "the lookup itself failed" so it
--- could be told apart from "confirmed gone". That theory did not hold:
--- `lib.nvim.git`'s own `git_system()` swallows *every* subprocess failure
--- (missing binary, a `safe.directory` refusal, a stale/disconnected network
--- mount the worktree lived on, ...) into a plain `nil`/`{}` -- it never
--- raises -- so the "ambiguous" branch was never actually reachable, and a
--- transient git failure on a perfectly healthy, still-checked-out session
--- silently read as confirmed-stale. Reading the ref straight off disk (the
--- same approach `current_branch()`'s own fallback above already uses, for
--- an unrelated reason -- avoiding a process spawn on the session-naming hot
--- path) sidesteps the whole class of failure: there is no external binary
--- to be missing, refuse, or hang.
---
--- Still returns `false` (not `nil`) rather than raising for input that
--- fails outright: an empty `cwd`/`branch`, or `cwd` not existing at all
--- (the same `false` git would eventually have answered anyway, and Issue
--- 5's own worked example is exactly "a removed worktree directory").
---@param cwd string
---@param branch string
---@return boolean
function M.branch_exists(cwd, branch)
  if type(cwd) ~= "string" or cwd == "" or type(branch) ~= "string" or branch == "" then
    return false
  end
  if vim.fn.isdirectory(cwd) == 0 then
    return false -- the directory itself is gone
  end
  local dotgit = find_gitdir(cwd)
  if not dotgit then
    return false -- no repo (anywhere upward from cwd) anymore
  end

  -- The common case: a loose ref file for a recently-active branch.
  local uv = vim.uv or vim.loop
  if uv.fs_stat(dotgit .. "/refs/heads/" .. branch) then
    return true
  end

  -- git periodically folds loose refs into a single `packed-refs` file
  -- (e.g. after `git gc`), so an older or less-active branch can be real
  -- and only live there: "<sha> refs/heads/<branch>" per line, a space
  -- between the two, plus comment lines (leading "#") and, on the line
  -- right *after* an annotated tag's own entry, a separate "^<sha>" peeled
  -- line -- neither format a plain trailing-string match on its own would
  -- reliably tell apart from a false match.
  --
  -- The space is required, not just a trailing match on "refs/heads/
  -- <branch>" alone: a branch whose own name happens to embed the literal
  -- substring "refs/heads/" as a path component (legal, if unusual --
  -- e.g. "sub/refs/heads/login") would otherwise satisfy a bare suffix
  -- check for an unrelated, shorter, nonexistent branch name too.
  local ok_lines, lines = pcall(vim.fn.readfile, dotgit .. "/packed-refs")
  if ok_lines and lines then
    local needle = " refs/heads/" .. branch
    for _, line in ipairs(lines) do
      if line:sub(1, 1) ~= "#" and line:sub(-#needle) == needle then
        return true
      end
    end
  end

  return false -- a real repo, but this branch genuinely isn't in it
end

--- Sanitize a string into a filesystem-safe session name segment: whitelist
--- word chars, dash and underscore; everything else becomes a dash.
---@param s string|nil  nil or empty -> ""
---@return string
function M.sanitize(s)
  if not s or s == "" then
    return ""
  end

  -- Strip ANSI escapes before trimming, or a trailing reset sequence keeps
  -- the string non-empty.
  s = s:gsub("\27%[[0-9;]*m", "")
  s = vim.trim(s)

  if s == "" then
    return ""
  end

  s = s:gsub("[^%w%-_]", "-") -- slashes, spaces, punctuation -> dash
  s = s:gsub("-+", "-")
  s = s:gsub("^-+", ""):gsub("-+$", "")

  return s
end

--- Resolve auto session name from project root and/or branch.
--- Returns default_name if no valid parts found (safe fallback).
---@param cfg Sessions.Config
---@return string
---@see sessions.core
function M.resolve_name(cfg)
  local parts = {}

  if cfg.project_aware then
    local root = M.project_root(cfg.project_markers)
    if root and root ~= "" then
      local basename = vim.fn.fnamemodify(root, ":t")
      if basename and basename ~= "" then
        local sanitized = M.sanitize(basename)
        if sanitized ~= "" then
          parts[#parts + 1] = sanitized
        end
      end
    end
  end

  if cfg.branch_aware then
    local branch = M.current_branch()
    if branch and branch ~= "" then
      local sanitized = M.sanitize(branch)
      if sanitized ~= "" then
        parts[#parts + 1] = sanitized
      end
    end
  end

  -- Only return auto-resolved name if we have valid parts
  -- Otherwise fall back to default_name (safe, prevents errors)
  if #parts > 0 then
    local resolved = table.concat(parts, "_")
    -- Final sanity check: resolved name should be mostly alphanumeric
    if resolved ~= "" and not resolved:match("^%-+$") then
      return resolved
    end
  end

  return cfg.default_name
end

return M
