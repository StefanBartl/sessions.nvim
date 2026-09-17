-- TESTS/layout_spec.lua — sessions.layout: window-split snapshots, the half of
-- a session that is about arrangement rather than about files.
--
-- A layout is captured from `winlayout()` with the window ids replaced by
-- sizes (ids do not survive a restart, sizes do) and restored by re-splitting
-- from whatever window is current. Real windows throughout: splitting and
-- measuring is exactly what the module does, and a mocked `winlayout()` would
-- only assert that the test knows the tree format.

return function(H)
  local layout = require("sessions.layout")
  local config = require("sessions.config")

  local dir, cleanup = H.fixture("layout")
  config.setup({ root = dir })
  local root = config.get().root

  ---@param node any  # a winlayout()-shaped tree
  ---@return string   # "row(leaf,col(leaf,leaf))"
  local function shape(node)
    if node[1] == "leaf" then
      return "leaf"
    end
    local parts = {}
    for i, child in ipairs(node[2]) do
      parts[i] = shape(child)
    end
    return node[1] .. "(" .. table.concat(parts, ",") .. ")"
  end

  vim.cmd("silent! only!")

  -- A name is required --------------------------------------------------------
  -- `:Session save-layout` takes the name as a required argument, but M.save is
  -- public API too and must not build `<root>/layouts/.json` out of nothing.
  local ok, err = layout.save("")
  H.falsy(ok, "an empty name is refused")
  H.eq(err, "layout name required", "with a reason")
  ---@diagnostic disable-next-line: param-type-mismatch
  H.falsy(layout.save(nil), "and so is no name at all")

  -- Nothing saved yet ---------------------------------------------------------
  H.eq(#layout.list(), 0, "no layouts directory yet -> an empty list")
  local miss_ok, miss_err = layout.restore("nope")
  H.falsy(miss_ok, "restoring a layout that was never saved fails")
  H.contains(miss_err, "corrupt or missing layout file", "with a reason naming the file")
  H.falsy(layout.delete("nope"), "and deleting one does too")

  -- Save ----------------------------------------------------------------------
  -- Three windows: a vertical split, the right half split horizontally, i.e.
  -- row(leaf, col(leaf, leaf)) -- deep enough that the recursion matters.
  vim.cmd("vsplit")
  vim.cmd("wincmd l") -- the new window opens left; split the right half instead
  vim.cmd("split")
  local live_shape = shape(vim.fn.winlayout())
  H.eq(live_shape, "row(leaf,col(leaf,leaf))", "the fixture layout is the nested one")

  local saved_ok, path = layout.save("three")
  H.ok(saved_ok, "save reports success")
  H.eq(path, root .. "/layouts/three.json", "and writes into <root>/layouts/")
  H.eq(vim.fn.filereadable(path), 1, "the file is there")

  local stored = require("lib.nvim.fs.json").read(path)
  H.ok(stored, "the layout file is valid JSON")
  ---@cast stored -nil
  H.eq(shape(stored), live_shape, "the stored tree has the live tree's shape")
  -- What a leaf carries is the *size*, not the window id it was captured
  -- from: ids are handed out fresh on every start, sizes are the thing worth
  -- restoring.
  H.eq(type(stored[2][1][2]), "table", "a leaf holds a table, not a window id")
  H.ok(stored[2][1][2].width, "and each leaf carries a width")
  H.ok(stored[2][1][2].height, "and a height")

  -- Restore -------------------------------------------------------------------
  vim.cmd("silent! only!")
  H.eq(shape(vim.fn.winlayout()), "leaf", "collapsed to a single window")

  local restored_ok, restored_path = layout.restore("three")
  H.ok(restored_ok, "restore reports success")
  H.eq(restored_path, path, "naming the file it used")
  H.eq(shape(vim.fn.winlayout()), live_shape, "and the split structure is back")

  -- Restore collapses first, so applying a layout twice is idempotent rather
  -- than cumulative -- otherwise every `:Session load-layout` would double the
  -- window count.
  layout.restore("three")
  H.eq(shape(vim.fn.winlayout()), live_shape, "restoring again does not stack more splits")

  -- Corrupt file --------------------------------------------------------------
  vim.fn.writefile({ "{ not json at all" }, path)
  local bad_ok, bad_err = layout.restore("three")
  H.falsy(bad_ok, "a corrupt layout file is refused")
  H.contains(bad_err, "corrupt or missing layout file", "with the same clear reason")

  -- Regression: the guard used to be `type(tree) ~= "table"`, which only
  -- rejects JSON that does not decode at all. Valid JSON that is not a layout
  -- tree -- `{}`, `[]`, an object, anything truncated to a table -- passed it,
  -- and `build()` then read `node[2]` as a child list and took its length: an
  -- uncaught "attempt to get length of a nil value" out of
  -- `:Session load-layout` instead of the "corrupt or missing layout file"
  -- the line above promises. `restore` now recursively validates the decoded
  -- shape (`is_valid_node`) before ever calling `build()`.
  vim.fn.writefile({ "{}" }, path)
  local empty_ok, empty_err = layout.restore("three")
  H.falsy(empty_ok, "an empty-table layout file is refused, not walked")
  H.contains(empty_err, "corrupt or missing layout file", "with the same clear reason")

  vim.fn.writefile({ "[]" }, path)
  local ok2, arr_err = layout.restore("three")
  H.falsy(ok2, "an empty-array layout file is refused too")
  H.contains(arr_err, "corrupt or missing layout file", "with the same reason")

  -- A node whose kind is neither "leaf" nor a split, or whose children are
  -- not a list, is refused the same way, however deep it hides.
  vim.fn.writefile({ '["row",[["leaf",{}],["nonsense",{}]]]' }, path)
  local ok3, nested_err = layout.restore("three")
  H.falsy(ok3, "a malformed node nested inside an otherwise valid tree is refused")
  H.contains(nested_err, "corrupt or missing layout file", "with the same reason, however deep")

  -- list ----------------------------------------------------------------------
  vim.cmd("silent! only!")
  H.ok(layout.save("beta"))
  H.ok(layout.save("alpha"))
  local names = vim.tbl_map(function(p)
    return vim.fn.fnamemodify(p, ":t:r")
  end, layout.list())
  H.eq(table.concat(names, ","), "alpha,beta,three", "list is sorted and holds every saved layout")

  -- delete --------------------------------------------------------------------
  local del_ok, del_path = layout.delete("beta")
  H.ok(del_ok, "delete reports success")
  H.eq(del_path, root .. "/layouts/beta.json", "naming the file it removed")
  H.eq(vim.fn.filereadable(del_path), 0, "which is gone")
  H.eq(#layout.list(), 2, "and out of the listing")

  -- Unwritable target ---------------------------------------------------------
  -- A root that cannot hold a layouts/ directory (here: a file sits where it
  -- would go) fails with a message rather than raising out of the command.
  local blocked = dir .. "/blocked"
  vim.fn.writefile({ "i am a file" }, blocked)
  config.setup({ root = blocked })
  local w_ok, w_err = layout.save("nope")
  H.falsy(w_ok, "saving under an unwritable root fails")
  H.contains(w_err, "failed to write", "with a message rather than an exception")

  config.setup({})
  cleanup()
end
