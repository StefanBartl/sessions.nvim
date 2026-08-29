---@diagnostic disable: missing-fields
-- The config and meta tables below carry only the fields the function under
-- test reads; a resolved Sessions.Config per case would be noise.
-- TESTS/resolve_name_spec.lua — sessions.git.resolve_name: which parts go into
-- an automatic session name, and what happens when none of them are available.

return function(H)
  local git = require("sessions.git")

  -- Both switches off ---------------------------------------------------------
  H.eq(
    git.resolve_name({ project_aware = false, branch_aware = false, default_name = "fallback" }),
    "fallback",
    "with nothing to derive from, the configured default is used"
  )

  -- The fallback is what makes this safe: a caller always gets a usable name
  -- back, so `:Session save` cannot end up writing to an empty path because the
  -- cwd happened to be somewhere without a project root or a branch.
  H.ok(git.resolve_name({
    project_aware = true,
    branch_aware = true,
    project_markers = { ".git" },
    default_name = "fallback",
  }) ~= "", "a name always comes back, whatever the environment offers")

  -- Project-aware -------------------------------------------------------------
  -- Run from the repo root, so the project part is this repository's own
  -- directory name -- sanitized, which is the part worth asserting.
  local project_only = git.resolve_name({
    project_aware = true,
    branch_aware = false,
    project_markers = { ".git" },
    default_name = "fallback",
  })
  H.ok(project_only ~= "", "a project name is produced inside a repository")
  H.eq(
    project_only,
    git.sanitize(project_only),
    "and it is already sanitized -- resolve_name never returns something sanitize would change"
  )
  H.excludes(project_only, "/", "no separator survives into the name")

  -- Composition ---------------------------------------------------------------
  -- With both switches on the parts are joined with an underscore. The branch
  -- part depends on the checkout, so the assertion is about the shape: the
  -- combined name starts with the project part and is at least as long.
  local both = git.resolve_name({
    project_aware = true,
    branch_aware = true,
    project_markers = { ".git" },
    default_name = "fallback",
  })
  H.ok(#both >= #project_only, "adding the branch never shortens the name")
  H.eq(both:sub(1, #project_only), project_only, "the project part comes first")
end
