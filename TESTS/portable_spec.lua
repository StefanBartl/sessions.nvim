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
  portable.make_relative(session, project)

  local stored = H.read(session)
  H.excludes(stored, project, "the saved cwd no longer appears literally")
  H.contains(stored, "{{SESSION_ROOT}}", "it is a placeholder now")
  H.contains(stored, "/elsewhere/outside.lua", "a path outside the project is left alone")

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

  -- boundary_replace: an overlapping match starting mid-needle --------------
  -- After a hit that fails the boundary check, the search must resume right
  -- after *that hit's start* (not past its end), or a valid match beginning
  -- one byte later inside the same run is skipped entirely. Needle "aa"
  -- against "aaa": the first "aa" (positions 1-2) is followed by another "a"
  -- (not a boundary) and is kept literal, but positions 2-3 is *also* "aa"
  -- and this time is followed by nothing (a boundary), so it must still be
  -- found and replaced.
  do
    local overlap_session = dir .. "/overlap.vim"
    vim.fn.writefile({ "before aaa after" }, overlap_session)
    portable.make_relative(overlap_session, "aa")
    H.eq(
      H.read(overlap_session),
      "before a{{SESSION_ROOT}} after",
      "a boundary-respecting match one byte into a rejected hit is still found"
    )
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
