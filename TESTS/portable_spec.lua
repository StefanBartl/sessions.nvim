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
