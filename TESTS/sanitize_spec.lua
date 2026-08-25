-- TESTS/sanitize_spec.lua — sessions.git.sanitize: turning a branch or a
-- directory name into something safe to put on disk.
--
-- This is the security-relevant one. A session name is used to build a file
-- path, and branch names are attacker-adjacent input in the sense that they
-- come from whatever the repository happens to contain. The function is a
-- whitelist rather than a blacklist, and these cases pin that it stays one.

return function(H)
  local git = require("sessions.git")

  -- Nothing in, nothing out ---------------------------------------------------
  H.eq(git.sanitize(nil), "", "nil is empty")
  H.eq(git.sanitize(""), "", "empty stays empty")
  H.eq(git.sanitize("   "), "", "whitespace only is empty")

  -- The ordinary case ---------------------------------------------------------
  H.eq(git.sanitize("main"), "main", "a plain name is unchanged")
  H.eq(git.sanitize("feat_x-1"), "feat_x-1", "word chars, dash and underscore all survive")

  -- Path separators are the point ---------------------------------------------
  H.eq(git.sanitize("feature/login"), "feature-login", "a slash cannot reach the filesystem")
  H.eq(git.sanitize("a\\b"), "a-b", "nor a backslash")
  H.eq(git.sanitize("../../etc/passwd"), "etc-passwd", "and neither can a traversal")
  H.excludes(git.sanitize("../../etc/passwd"), "..", "no dot-dot survives")

  -- Everything else outside the whitelist -------------------------------------
  H.eq(git.sanitize("release 1.0"), "release-1-0", "spaces and dots become dashes")
  H.eq(git.sanitize("fix:#42"), "fix-42", "punctuation too")

  -- ANSI escapes are stripped before anything else ----------------------------
  -- `git branch --show-current` can come back coloured depending on the user's
  -- git config; the escape bytes must not end up in a filename.
  H.eq(git.sanitize("\27[32mmain\27[0m"), "main", "colour codes are removed, not dashed")

  -- Cosmetics -----------------------------------------------------------------
  H.eq(git.sanitize("a//b"), "a-b", "runs of dashes collapse")
  H.eq(git.sanitize("/lead/"), "lead", "leading and trailing dashes are trimmed")
  H.eq(git.sanitize("///"), "", "a name made only of separators sanitizes to nothing")
end
