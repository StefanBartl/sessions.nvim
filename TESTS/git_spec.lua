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

  cd(start_cwd)
  cleanup()
end
