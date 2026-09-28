-- TESTS/git_spec.lua — sessions.git beyond `sanitize`: where a branch name and
-- a project root actually come from.
--
-- Both getters have two halves. lib.nvim answers when it is installed, and a
-- process-free fallback answers when it is not: `.git/HEAD` read as a file for
-- the branch, `vim.fs.find(..., upward = true)` for the root. The fallback is
-- the interesting half — it exists precisely so that resolving a session name
-- never spawns `git`, and it is the half a machine without lib.nvim runs.
--
-- Nothing here shells out. The "repositories" are directories with a `.git`
-- written by hand, which is all the fallback ever looks at.

return function(H)
  local git = require("sessions.git")

  local dir, cleanup = H.fixture("git")
  local start_cwd = vim.fn.getcwd()
  local function cd(path)
    vim.cmd("cd " .. vim.fn.fnameescape(path))
  end

  -- ---------------------------------------------- current_branch, via lib.nvim

  local restore = H.stub("lib.nvim.git", {
    current_branch = function()
      return "dev"
    end,
  })
  H.eq(git.current_branch(), "dev", "lib.nvim's answer is used when it is installed")
  restore()

  -- lib.nvim reports failure by *returning* a message rather than raising, so
  -- the guard is a string check. Without it, "Error: not a git repository"
  -- would sanitize into a session name and a file called `Error-not-a-git-...`
  -- would appear on disk.
  for _, bad in ipairs({ "Error: not a git repository", "fatal ERROR", "" }) do
    local undo = H.stub("lib.nvim.git", {
      current_branch = function()
        return bad
      end,
    })
    H.falsy(git.current_branch(), ("an error-like answer (%q) is refused"):format(bad))
    undo()
  end

  local undo_nil = H.stub("lib.nvim.git", {
    current_branch = function()
      return nil
    end,
  })
  H.falsy(git.current_branch(), "and so is no answer at all")
  undo_nil()

  -- ------------------------------------------- current_branch, the fallback

  local no_lib = H.stub("lib.nvim.git", false)

  -- A .git directory, the ordinary case.
  local repo = dir .. "/repo"
  vim.fn.mkdir(repo .. "/.git", "p")
  vim.fn.writefile({ "ref: refs/heads/feature/login" }, repo .. "/.git/HEAD")
  cd(repo)
  H.eq(git.current_branch(), "feature/login", ".git/HEAD names the branch")

  -- Detached HEAD carries a raw SHA: there is no branch, and nil is the right
  -- answer (resolve_name then falls back to the project part or default_name).
  vim.fn.writefile({ "9f6c4b1d0e2a3b5c7d8e9f0a1b2c3d4e5f607182" }, repo .. "/.git/HEAD")
  H.falsy(git.current_branch(), "a detached HEAD has no branch name")

  -- An unreadable/garbage HEAD is the same "no branch", not an error.
  vim.fn.writefile({ "gibberish" }, repo .. "/.git/HEAD")
  H.falsy(git.current_branch(), "a HEAD that names nothing yields nothing")
  vim.fn.delete(repo .. "/.git/HEAD")
  H.falsy(git.current_branch(), "a .git directory without a HEAD yields nothing")

  -- A worktree or submodule: .git is a *file* pointing at the real git dir.
  local wt = dir .. "/worktree"
  local realgit = dir .. "/realgit"
  vim.fn.mkdir(wt, "p")
  vim.fn.mkdir(realgit, "p")
  vim.fn.writefile({ "ref: refs/heads/wt-branch" }, realgit .. "/HEAD")
  vim.fn.writefile({ "gitdir: " .. realgit }, wt .. "/.git")
  cd(wt)
  H.eq(git.current_branch(), "wt-branch", "a .git file's absolute gitdir is followed")

  -- The same, spelled relative to the worktree -- which is what `git worktree
  -- add` actually writes for a worktree inside the repository.
  vim.fn.writefile({ "gitdir: ../realgit" }, wt .. "/.git")
  H.eq(git.current_branch(), "wt-branch", "and so is a relative one")

  vim.fn.writefile({ "not a gitdir line" }, wt .. "/.git")
  H.falsy(git.current_branch(), "a .git file that points nowhere yields nothing")

  -- No .git in the fixture at all: the search walks upward, and inside this
  -- checkout it legitimately finds the repository's own one. That upward walk
  -- is the behaviour worth pinning -- a session saved in a subdirectory of a
  -- project still resolves that project's branch.
  local deep = dir .. "/deep/nested/dir"
  vim.fn.mkdir(deep, "p")
  cd(deep)
  local from_deep = git.current_branch()
  cd(start_cwd)
  H.eq(from_deep, git.current_branch(), "the upward walk finds the enclosing repository")

  no_lib()

  -- ------------------------------------------------ current_branch_no_spawn
  -- Same question as current_branch(), but must NEVER prefer lib.nvim.git
  -- even when it IS installed -- always the direct .git/HEAD read, for a
  -- caller on a much higher-frequency path (sessions.chip_text's "modern"
  -- text, re-read on every ui.kit.chip refresh) where current_branch()'s
  -- own subprocess-preferring default would be a real, measurable cost.

  local ns_repo = dir .. "/no-spawn-repo"
  vim.fn.mkdir(ns_repo .. "/.git", "p")
  vim.fn.writefile({ "ref: refs/heads/no-spawn-branch" }, ns_repo .. "/.git/HEAD")
  cd(ns_repo)

  -- lib.nvim.git IS installed here (no `no_lib()` stub active) and would
  -- answer something completely different -- current_branch() itself
  -- would prefer it (confirmed first, for contrast); current_branch_no_spawn()
  -- must ignore it regardless and read .git/HEAD directly instead.
  local lib_says_something_else = H.stub("lib.nvim.git", {
    current_branch = function()
      return "SPAWNED-VIA-LIB-NVIM-GIT"
    end,
  })
  H.eq(
    git.current_branch(),
    "SPAWNED-VIA-LIB-NVIM-GIT",
    "current_branch() itself does prefer lib.nvim.git when installed"
  )
  H.eq(
    git.current_branch_no_spawn(),
    "no-spawn-branch",
    "...but current_branch_no_spawn() never does, even then"
  )
  lib_says_something_else()

  cd(start_cwd)

  -- ------------------------------------------------------------ project_root

  local undo_root = H.stub("lib.nvim.fs.find_upward_dir", function()
    return "/found/by/lib"
  end)
  H.eq(git.project_root({ ".git" }), "/found/by/lib", "lib.nvim answers when installed")
  undo_root()

  for _, bad in ipairs({ "Error: nothing found", "" }) do
    local undo = H.stub("lib.nvim.fs.find_upward_dir", function()
      return bad
    end)
    H.falsy(git.project_root({ ".git" }), ("an error-like root (%q) is refused"):format(bad))
    undo()
  end

  local no_find = H.stub("lib.nvim.fs.find_upward_dir", false)

  local proj = dir .. "/proj/src"
  vim.fn.mkdir(proj, "p")
  vim.fn.writefile({ "all:" }, dir .. "/proj/Makefile")
  cd(proj)
  H.eq(
    vim.fs.normalize(git.project_root({ "Makefile" }) or ""),
    vim.fs.normalize(dir .. "/proj"),
    "the fallback finds the directory holding the marker, from a subdirectory"
  )
  H.falsy(git.project_root({ "no-such-marker-9f6c4b1d" }), "a marker nothing carries finds no root")
  cd(start_cwd)

  no_find()

  -- ----------------------------------------------------- resolve_name, exactly
  -- resolve_name_spec.lua asserts the *shape* against whatever checkout it runs
  -- in. With both sources stubbed the composition can be pinned literally.

  local fake_branch = H.stub("lib.nvim.git", {
    current_branch = function()
      return "feature/login"
    end,
  })
  local fake_root = H.stub("lib.nvim.fs.find_upward_dir", function()
    return "/home/me/My Project"
  end)

  ---@diagnostic disable-next-line: missing-fields
  local cfg = {
    project_aware = true,
    branch_aware = true,
    project_markers = { ".git" },
    default_name = "fallback",
  }
  H.eq(
    git.resolve_name(cfg),
    "My-Project_feature-login",
    "project first, branch second, joined by _"
  )

  cfg.branch_aware = false
  H.eq(git.resolve_name(cfg), "My-Project", "branch_aware = false drops the branch part")
  cfg.branch_aware = true
  cfg.project_aware = false
  H.eq(git.resolve_name(cfg), "feature-login", "project_aware = false drops the project part")
  cfg.project_aware = true

  fake_root()
  local root_root = H.stub("lib.nvim.fs.find_upward_dir", function()
    return "/"
  end)
  local blank_branch = H.stub("lib.nvim.git", {
    current_branch = function()
      return "///"
    end,
  })
  -- Both parts sanitize away to nothing: the configured default is what keeps
  -- `:Session save` from building a path with an empty name in it.
  H.eq(
    git.resolve_name(cfg),
    "fallback",
    "parts that sanitize to nothing fall back to default_name"
  )
  blank_branch()
  root_root()
  fake_branch()

  -- ----------------------------------------------------------- branch_exists
  -- Purely filesystem-based -- real, hand-written .git directories, same
  -- fixture style current_branch()'s own fallback tests above already use.
  -- Deliberately NOT stubbed through lib.nvim.git: an earlier version of
  -- this went through lib.nvim.git.in_git_repo()/.refs(), on the theory
  -- that a raised Lua error meant "the lookup itself failed" -- but the
  -- real lib.nvim.git swallows every subprocess failure into a plain
  -- nil/{} and never raises, so that branch was never actually reachable,
  -- and a transient git failure on a healthy session read as confirmed-
  -- stale. Rewritten around find_gitdir()'s own filesystem read instead,
  -- which has no external binary to be missing, refuse, or hang.

  H.eq(
    git.branch_exists(dir .. "/does-not-exist-at-all", "main"),
    false,
    "a missing directory: false"
  )

  -- A real, empty `.git` right at this exact directory (a fresh `git init`
  -- with zero commits) -- deliberately NOT "a directory with no .git
  -- anywhere upward at all": every fixture here lives inside TESTS/, itself
  -- inside this repo's own checkout, so an upward search from ANY fixture
  -- subdirectory legitimately finds THIS repo's own .git (exactly the
  -- behaviour current_branch()'s own fallback test above already covers
  -- and relies on -- a session saved from a subdirectory must still
  -- resolve the enclosing project). Nothing above `dir` is faked away here.
  local empty_repo = dir .. "/empty-repo"
  vim.fn.mkdir(empty_repo .. "/.git", "p")
  H.eq(git.branch_exists(empty_repo, "main"), false, "a real repo with zero refs at all: false")

  local repo_dir = dir .. "/branch-exists-repo"
  vim.fn.mkdir(repo_dir .. "/.git/refs/heads", "p")
  vim.fn.writefile({ "ref: refs/heads/main" }, repo_dir .. "/.git/HEAD")
  vim.fn.writefile({ "" }, repo_dir .. "/.git/refs/heads/main") -- a loose ref: the file existing is what matters

  H.eq(git.branch_exists(repo_dir, "main"), true, "a branch with a loose ref file: true")
  H.eq(
    git.branch_exists(repo_dir, "long-gone"),
    false,
    "one with no ref at all, loose or packed: false"
  )

  -- git periodically folds loose refs into packed-refs (e.g. after
  -- `git gc`) -- a branch can be real and only live there.
  vim.fn.writefile({
    "# pack-refs with: peeled fully-sorted sorted",
    "9f6c4b1d0e2a3b5c7d8e9f0a1b2c3d4e5f607182 refs/heads/feature/login",
    "1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d refs/tags/v1.0.0",
    "^9f6c4b1d0e2a3b5c7d8e9f0a1b2c3d4e5f607182", -- a peeled annotated-tag marker, not a ref of its own
  }, repo_dir .. "/.git/packed-refs")
  H.eq(
    git.branch_exists(repo_dir, "feature/login"),
    true,
    "a branch only in packed-refs: still true"
  )
  H.eq(
    git.branch_exists(repo_dir, "v1.0.0"),
    false,
    "a TAG in packed-refs is not a branch, even with the same name shape"
  )

  -- Regression, found by a second review round: a branch whose OWN name
  -- happens to embed "refs/heads/" as a path component (legal, if
  -- unusual) must not satisfy a bare suffix match for an unrelated,
  -- shorter, nonexistent branch name -- the match needs the packed-refs
  -- field boundary (a space right before it), not just a trailing
  -- substring.
  vim.fn.writefile({
    "9f6c4b1d0e2a3b5c7d8e9f0a1b2c3d4e5f607182 refs/heads/sub/refs/heads/login",
  }, repo_dir .. "/.git/packed-refs")
  H.eq(
    git.branch_exists(repo_dir, "login"),
    false,
    "a branch embedding refs/heads/ in its own name doesn't false-match a shorter one"
  )
  H.eq(
    git.branch_exists(repo_dir, "sub/refs/heads/login"),
    true,
    "...but the real, full branch name still matches"
  )

  os.remove(repo_dir .. "/.git/packed-refs")

  -- A worktree/submodule: .git is a FILE pointing elsewhere -- find_gitdir()
  -- (shared with current_branch()'s own fallback, already covered above)
  -- follows it the same way.
  local be_wt = dir .. "/branch-exists-worktree"
  vim.fn.mkdir(be_wt, "p")
  vim.fn.mkdir(repo_dir .. "/.git/refs/heads", "p")
  vim.fn.writefile({ "gitdir: " .. repo_dir .. "/.git" }, be_wt .. "/.git")
  H.eq(
    git.branch_exists(be_wt, "main"),
    true,
    "a worktree's .git FILE is followed to the real gitdir"
  )

  -- A session saved from a SUBDIRECTORY of the repo still resolves --
  -- find_gitdir() walks upward, same as current_branch()'s own fallback.
  local be_deep = repo_dir .. "/deep/nested/dir"
  vim.fn.mkdir(be_deep, "p")
  H.eq(git.branch_exists(be_deep, "main"), true, "the upward walk finds the enclosing repository")

  H.eq(git.branch_exists("", "main"), false, "an empty cwd is refused rather than guessed at")
  H.eq(git.branch_exists(repo_dir, ""), false, "so is an empty branch name")

  cd(start_cwd)
  cleanup()
end
