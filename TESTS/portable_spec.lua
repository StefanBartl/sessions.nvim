-- TESTS/portable_spec.lua — sessions.portable: making a .vim session file stop
-- pinning itself to the machine it was saved on, and re-anchoring it on load.
--
-- The pair has to be exact: `make_relative` writes a placeholder into the
-- stored file, `prepare_for_load` swaps it back out into a *copy*. If the
-- second one mutated the stored file instead, a session shared across two
-- machines would be rewritten for whichever one opened it last.

return function(H)
  local portable = require("sessions.portable")

  local dir, cleanup = H.fixture("portable")
  local project = dir .. "/project"
  vim.fn.mkdir(project, "p")

  local session = dir .. "/session.vim"
  local function write_session(lines)
    vim.fn.writefile(lines, session)
  end

  -- make_relative -------------------------------------------------------------
  write_session({
    "cd " .. project,
    "badd +1 " .. project .. "/lua/init.lua",
    "badd +1 /elsewhere/outside.lua",
  })
  local rel_ok = portable.make_relative(session, project)
  H.ok(rel_ok, "make_relative reports success (ERR-03: an explicit boolean, not a silent no-op)")

  local stored = H.read(session)
  H.excludes(stored, project, "the saved cwd no longer appears literally")
  H.contains(stored, "{{SESSION_ROOT}}", "it is a placeholder now")
  H.contains(stored, "/elsewhere/outside.lua", "a path outside the project is left alone")

  -- make_relative on a file that cannot be read fails explicitly rather than
  -- silently doing nothing (ERR-03).
  local missing = dir .. "/does-not-exist-either.vim"
  local miss_ok, miss_err = portable.make_relative(missing, project)
  H.falsy(miss_ok, "make_relative on a missing file reports failure")
  H.ok(miss_err, "with a reason")

  -- an empty session file is an error on save (the wrapper's own contract)
  do
    local empty = dir .. "/empty.vim"
    vim.fn.writefile({}, empty)
    local e_ok, e_err = portable.make_relative(empty, project)
    H.falsy(e_ok, "make_relative on an empty file reports failure")
    H.ok(e_err, "with a reason")
  end

  -- an empty cwd (deleted working directory) is reported, never thrown
  do
    local before = H.read(session)
    local c_ok, c_res = pcall(portable.make_relative, session, "")
    H.ok(c_ok, "make_relative with an empty cwd does not throw")
    H.falsy(c_res, "and reports failure")
    local r_ok, r_res, r_temp, r_err = pcall(portable.prepare_for_load, session, "")
    H.ok(r_ok, "prepare_for_load with an empty cwd does not throw")
    H.eq(r_res, session, "it hands the stored file back")
    H.falsy(r_temp, "without a temporary copy")
    H.ok(r_err, "and a reason")
    H.eq(H.read(session), before, "the stored file is untouched")
  end

  -- boundary_replace: a sibling that merely starts with the same text -------
  -- `E:/repos/ui.nvim` is a prefix of `E:/repos/ui.nvim-backup`, common in a
  -- repos folder full of similarly-named plugin checkouts. A plain `gsub` on
  -- the literal cwd would match that prefix too and corrupt the sibling's
  -- path; the real boundary check is that the byte right after the match is
  -- not itself a filename-continuation character (word char, `.`, `-`, `~`).
  do
    local sibling_dir = dir .. "/ui.nvim"
    local sibling_session = dir .. "/sibling.vim"
    vim.fn.writefile({
      "badd +1 " .. sibling_dir .. "/init.lua",
      "badd +1 " .. sibling_dir .. "-backup/init.lua",
    }, sibling_session)

    portable.make_relative(sibling_session, sibling_dir)
    local sibling_stored = H.read(sibling_session)
    H.contains(sibling_stored, "{{SESSION_ROOT}}/init.lua", "the project's own path is rewritten")
    H.contains(
      sibling_stored,
      sibling_dir .. "-backup/init.lua",
      "but a sibling that only shares the prefix is left exactly as it was"
    )
    H.excludes(
      sibling_stored,
      "{{SESSION_ROOT}}-backup",
      "and never gets the placeholder spliced into its own name"
    )
  end

  -- an overlapping match starting mid-needle -------------------------------
  -- The substitution is `lib.nvim.fs.portable`'s, which checks BOTH ends of a
  -- path: the byte after the match must not continue a file name, and the byte
  -- before must not be a name character or a separator either (the root
  -- `/home/me` must not be replaced inside `/srv/home/me/x`). Needle "aa"
  -- against "aaa": the first "aa" is followed by another "a" (rejected), and
  -- the one starting a byte later is PRECEDED by an "a" (rejected too), so
  -- nothing is replaced. A real path root is never glued to a longer name.
  do
    local overlap_session = dir .. "/overlap.vim"
    vim.fn.writefile({ "before aaa after" }, overlap_session)
    portable.make_relative(overlap_session, "aa")
    H.eq(
      H.read(overlap_session),
      "before aaa after",
      "a root that is only part of a longer name, at either end, is left alone"
    )
  end

  -- a root in the middle of another path ------------------------------------
  do
    local mid_session = dir .. "/mid.vim"
    vim.fn.writefile({ "badd +1 /srv/home/me/x.lua", "badd +1 /home/me/y.lua" }, mid_session)
    portable.make_relative(mid_session, "/home/me")
    local mid = H.read(mid_session)
    H.contains(
      mid,
      "/srv/home/me/x.lua",
      "a path that merely contains the root in its middle is untouched"
    )
    H.contains(mid, "{{SESSION_ROOT}}/y.lua", "the project's own path is rewritten")
  end

  -- prepare_for_load ----------------------------------------------------------
  local elsewhere = dir .. "/moved"
  vim.fn.mkdir(elsewhere, "p")

  local load_path, is_copy = portable.prepare_for_load(session, elsewhere, nil)
  H.ok(is_copy, "rewriting produces a copy")
  H.ok(load_path ~= session, "and the copy is a different file")
  H.contains(H.read(load_path), elsewhere, "the placeholder is anchored to the new cwd")
  H.contains(
    H.read(session),
    "{{SESSION_ROOT}}",
    "while the stored file still holds the placeholder, so it stays portable"
  )

  -- No rewriting needed -------------------------------------------------------
  -- A file with nothing to substitute is handed back as-is rather than copied,
  -- so the common case does not litter the temp directory.
  local plain = dir .. "/plain.vim"
  vim.fn.writefile({ "set nocompatible" }, plain)
  local same, copied = portable.prepare_for_load(plain, elsewhere, nil)
  H.eq(same, plain, "an unaffected file is returned unchanged")
  H.falsy(copied, "and is not reported as a copy")

  -- root_remap ----------------------------------------------------------------
  -- The other half of portability: paths that were never under the project
  -- root, translated by an explicit prefix mapping.
  local remap_src = dir .. "/remap.vim"
  vim.fn.writefile({ "badd +1 /old/root/file.lua" }, remap_src)
  local remapped = portable.prepare_for_load(remap_src, elsewhere, { ["/old/root"] = "/new/root" })
  H.contains(H.read(remapped), "/new/root/file.lua", "a remapped prefix is translated")
  H.excludes(H.read(remap_src), "/new/root", "and again the stored file is untouched")

  -- Empty/missing file --------------------------------------------------------
  local gone = dir .. "/does-not-exist.vim"
  local gone_path, gone_copy = portable.prepare_for_load(gone, elsewhere, nil)
  H.eq(gone_path, gone, "a missing file is returned as-is")
  H.falsy(gone_copy, "and reports no copy")

  cleanup()
end
