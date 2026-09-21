-- TESTS/marks_spec.lua — sessions.marks: the ordered file list, its pins and
-- defaults, the harpoon import, the editable menu and the preview.
--
-- Everything runs against a fixture directory: the store under a private
-- session root, the marked files created on the spot. Nothing here reads
-- the real `stdpath("data")` -- the one code path that would (the harpoon
-- import) is pointed at a fixture data directory. `vim.fn.confirm` is
-- replaced for the pinned-removal prompt, since a headless run cannot
-- answer one.

return function(H)
  local config = require("sessions.config")

  local dir, cleanup = H.fixture("marks")
  vim.cmd("silent! %bwipeout!")

  local function file(name, lines)
    local p = dir .. "/" .. name
    vim.fn.writefile(lines or { name .. " line 1", "line 2", "line 3" }, p)
    return vim.fs.normalize(p)
  end
  local a = file("a.md")
  local b = file("b.lua")
  local c = file("c.txt")
  local d = file("d.md")

  config.setup({
    root = dir .. "/sroot",
    branch_aware = false,
    project_aware = false,
    marks = {
      enable = true,
      scope = "global",
      defaults = { { dir, "a.md" }, b, { dir, "does-not-exist.md" } },
      import_harpoon = false,
      context_debounce_ms = 0,
    },
  })

  local marks = H.fresh("sessions.marks")

  -- specs and scope -------------------------------------------------------

  H.eq(marks.scope_key(), "global", "global scope has a fixed key")
  H.contains(marks.store_path(), "/marks/global.json", "store lives under root/marks")
  H.eq(
    marks.resolve_spec({ "$NVIM_HOME", "init.lua" }),
    marks.canon(vim.fn.stdpath("config") .. "/init.lua"),
    "$NVIM_HOME expands to the config dir"
  )
  H.eq(marks.resolve_spec({ "$HOME" }) ~= "", true, "$HOME expands")
  H.eq(marks.resolve_spec({}), "", "an empty spec is no path")
  H.eq(marks.resolve_spec(b), b, "a plain string is taken as-is")

  local defaults = marks.defaults()
  H.eq(#defaults, 3, "defaults resolve in order, missing files included")
  H.eq(defaults[1], a, "...first the segment spec")
  H.eq(defaults[2], b, "...then the string")
  H.ok(marks.is_pinned(a), "a config default counts as pinned")
  H.falsy(marks.is_pinned(c), "an unlisted file does not")

  -- empty store -------------------------------------------------------------

  H.eq(#marks.list(), 0, "nothing listed before anything was added")
  local ok_sel, err_sel = marks.select(1)
  H.falsy(ok_sel, "select on an empty list fails")
  H.contains(err_sel, "no mark at 1", "...and says so")

  -- add / remove ------------------------------------------------------------

  H.ok(marks.add(c), "add a file")
  H.ok(marks.add(d), "add another")
  H.eq(#marks.list(), 2, "two listed")
  H.eq(marks.list()[1].path, c, "in insertion order")
  local ok_again, note = marks.add(c)
  H.ok(ok_again, "adding twice is fine")
  H.eq(note, "already listed", "...and reported as a no-op")
  H.eq(#marks.list(), 2, "...without a duplicate")

  H.ok(marks.add(d, { front = true }), "add --front moves an existing entry")
  H.eq(marks.list()[1].path, d, "...to slot 1")
  H.eq(marks.list()[2].path, c, "...the other shifts down")
  H.eq(marks.index(c), 2, "index() finds it")
  H.eq(marks.index(a), nil, "index() of an unlisted file is nil")

  local ok_rm, err_rm = marks.add(dir .. "/nope.md")
  H.falsy(ok_rm, "adding a missing file fails")
  H.contains(err_rm, "not an existing file", "...with the reason")

  H.ok(marks.remove(d), "remove")
  H.eq(#marks.list(), 1, "one left")
  local ok_rm2, err_rm2 = marks.remove(d)
  H.falsy(ok_rm2, "removing again fails")
  H.contains(err_rm2, "not in the list", "...saying it is not listed")

  -- the store is a file, and survives a fresh module -----------------------

  H.eq(vim.fn.filereadable(marks.store_path()), 1, "the store file exists")
  local again = H.fresh("sessions.marks")
  H.eq(#again.list(), 1, "a fresh module reads the same list")
  H.eq(again.list()[1].path, c, "...with the same entry")
  marks = again

  -- defaults sync / reset ---------------------------------------------------

  H.eq(marks.defaults_sync(), 2, "sync appends the two existing defaults")
  H.eq(#marks.list(), 3, "...after what was there")
  H.eq(marks.list()[1].path, c, "existing entries keep their place")
  H.eq(marks.list()[2].path, a, "defaults follow in defaults order")
  H.eq(marks.list()[3].path, b, "...")
  H.eq(marks.defaults_sync(), 0, "a second sync adds nothing")

  H.ok(marks.update_context(a, 3, 2), "remember a cursor position")
  H.eq(marks.list()[2].row, 3, "...row stored")
  H.eq(marks.list()[2].col, 2, "...col stored")
  H.falsy(marks.update_context(a, 3, 2), "the same position is not a change")
  H.falsy(marks.update_context(dir .. "/unlisted.md", 1, 0), "an unlisted file is ignored")

  -- update_contexts: one read, one write for a whole batch (fix: the
  -- debounced BufLeave flush used to call update_context per pending
  -- file, each doing its own store read+write -- costing N of each for a
  -- burst touching N marked files instead of the "one write" this
  -- module's own header promises).
  do
    local json = require("lib.nvim.fs.json")
    local real_write = json.write
    local writes = 0
    json.write = function(...)
      writes = writes + 1
      return real_write(...)
    end
    local changed =
      marks.update_contexts({ [c] = { row = 5, col = 1 }, [b] = { row = 6, col = 2 } })
    json.write = real_write
    H.ok(changed, "update_contexts reports a change")
    H.eq(writes, 1, "...in exactly one store write for two files")
    H.eq(marks.list()[marks.index(c)].row, 5, "...c's position updated")
    H.eq(marks.list()[marks.index(b)].row, 6, "...b's position updated")
    H.falsy(marks.update_contexts({}), "an empty batch is a no-op")
    H.falsy(marks.update_contexts(nil), "a nil batch is a no-op")
  end

  H.eq(marks.defaults_reset(), 2, "reset yields exactly the existing defaults")
  H.eq(marks.list()[1].path, a, "...in defaults order")
  H.eq(marks.list()[1].row, 3, "...keeping the remembered position")
  H.eq(marks.index(c), nil, "...and drops what was not a default")

  -- pin / unpin -------------------------------------------------------------

  H.ok(marks.pin(c, { front = true }), "pin a file")
  H.ok(marks.is_pinned(c), "...it is a pin now")
  H.eq(marks.list()[1].path, c, "...and sits first")
  H.eq(vim.fn.filereadable(marks.pins_path()), 1, "pins are stored in their own file")
  local ok_pin2, note_pin = marks.pin(c)
  H.ok(ok_pin2, "pinning twice is fine")
  H.eq(note_pin, "already pinned", "...and says so")

  H.ok(marks.unpin(c), "unpin")
  H.falsy(marks.is_pinned(c), "...no longer a pin")
  H.ok(marks.index(c), "...but still listed")
  local ok_up, err_up = marks.unpin(a)
  H.falsy(ok_up, "a config default cannot be unpinned")
  H.contains(err_up, "config default", "...and the reason names marks.defaults")
  local ok_up2, err_up2 = marks.unpin(d)
  H.falsy(ok_up2, "unpinning a non-pin fails")
  H.contains(err_up2, "not a pin", "...")

  -- add --permanent = add + pin
  H.ok(marks.add(d, { permanent = true }), "add --permanent")
  H.ok(marks.is_pinned(d), "...pins as well")
  H.ok(marks.unpin(d), "clean up the pin")

  -- set_paths: what the edit menu hands back ---------------------------------

  marks.update_context(c, 2, 1)
  local items = marks.set_paths({ "", b, "  " .. c .. "  ", b, d })
  H.eq(#items, 3, "blanks and duplicates are dropped")
  H.eq(items[1].path, b, "order is the lines' order")
  H.eq(items[2].path, c, "...")
  H.eq(items[2].row, 2, "a survivor keeps its position")
  H.eq(items[3].path, d, "a new line is added")
  H.eq(marks.index(a), nil, "a line that is gone is removed")

  -- select ------------------------------------------------------------------

  local ok_s = marks.select(2)
  H.ok(ok_s, "select opens the entry")
  H.eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), c, "...in the current window")
  H.eq(vim.api.nvim_win_get_cursor(0)[1], 2, "...at the remembered row")
  local ok_s9, err_s9 = marks.select(9)
  H.falsy(ok_s9, "select past the end fails")
  H.contains(err_s9, "3 listed", "...with the count")

  -- debug lines ---------------------------------------------------------------

  local dbg = table.concat(marks.debug_lines(), "\n")
  H.contains(dbg, "scope: global", "debug names the scope")
  H.contains(dbg, "items: 3", "...and the count")
  H.contains(dbg, "📌", "...and flags a pinned entry")

  -- harpoon import ------------------------------------------------------------

  local hdir = dir .. "/harpoon"
  vim.fn.mkdir(hdir, "p")
  local bucket = "C:/some/config"
  local function encoded(path, row, col)
    return vim.json.encode({ value = path, context = { row = row, col = col } })
  end
  vim.fn.writefile({
    vim.json.encode({
      [bucket] = {
        __harpoon_files = { encoded(d, 7, 3), encoded(a, 1, 0), encoded(dir .. "/gone.md", 1, 0) },
      },
      ["E:/other"] = { __harpoon_files = { encoded(c, 1, 0) } },
    }),
  }, hdir .. "/one.json")
  vim.fn.writefile({ "[]" }, hdir .. "/empty.json")

  H.eq(#marks.harpoon_data_files(hdir), 2, "both data files are found")
  H.eq(
    marks.read_harpoon_bucket(hdir .. "/one.json", "c:\\some\\config") ~= nil,
    true,
    "bucket keys compare normalized"
  )
  H.eq(marks.read_harpoon_bucket(hdir .. "/one.json", "/nowhere"), nil, "a missing bucket is nil")

  local imported, ierr = marks.import_harpoon({ bucket = bucket, data_dir = hdir })
  H.eq(ierr, nil, "import succeeds")
  H.eq(imported, 2, "two existing files imported, the missing one skipped")
  local after = marks.list()
  H.eq(after[1].path, d, "harpoon's order first")
  H.eq(after[1].row, 7, "...with harpoon's cursor row")
  H.eq(after[2].path, a, "...")
  H.eq(#after, 4, "then what was already listed and not in harpoon")
  local _, none_err = marks.import_harpoon({ bucket = "/nowhere", data_dir = hdir })
  H.contains(none_err, "no harpoon bucket", "an unknown bucket is reported")

  -- first-run seeding ------------------------------------------------------------

  config.setup({
    root = dir .. "/sroot2",
    branch_aware = false,
    project_aware = false,
    marks = { enable = true, defaults = { a }, import_harpoon = false },
  })
  marks = H.fresh("sessions.marks")
  H.eq(marks.seed_once(), "defaults", "first run seeds from the defaults")
  H.eq(#marks.list(), 1, "...one default listed")
  H.eq(marks.seed_once(), nil, "a second call does nothing")
  marks.remove(a)
  H.eq(marks.seed_once(), nil, "...even with the list emptied on purpose")

  config.setup({
    root = dir .. "/sroot3",
    branch_aware = false,
    project_aware = false,
    marks = { enable = true, defaults = { a }, import_harpoon = true },
  })
  marks = H.fresh("sessions.marks")
  H.eq(
    marks.seed_once({ bucket = bucket, data_dir = hdir }),
    "harpoon",
    "with a harpoon list, that wins"
  )
  H.eq(marks.list()[1].path, d, "...harpoon's first entry first")
  H.ok(marks.index(a), "...and the defaults are synced in")

  -- project scope -------------------------------------------------------------------

  config.setup({
    root = dir .. "/sroot4",
    branch_aware = false,
    project_aware = false,
    marks = { enable = true, scope = "project", import_harpoon = false },
  })
  marks = H.fresh("sessions.marks")
  local pkey = marks.scope_key()
  H.ok(pkey ~= "global", "project scope has its own key")
  H.ok(pkey:match("^[%w%._%-]+$"), "...safe as a file name: " .. pkey)
  H.contains(marks.store_path(), "/marks/" .. pkey .. ".json", "...and its own store")

  -- the edit menu -------------------------------------------------------------------

  config.setup({
    root = dir .. "/sroot5",
    branch_aware = false,
    project_aware = false,
    marks = { enable = true, defaults = { a }, import_harpoon = false, context_debounce_ms = 0 },
  })
  marks = H.fresh("sessions.marks")
  local menu = H.fresh("sessions.marks.menu")
  marks.add(a)
  marks.add(c)

  local buf = menu.open_edit()
  H.ok(buf, "the edit menu opens")
  H.ok(menu.is_open(), "...and is open")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  H.eq(#lines, 2, "one line per mark")
  H.eq(lines[1], a, "...the path itself")
  H.eq(vim.bo[buf].filetype, "sessions-marks", "its own filetype")

  -- Reorder and save with :w.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { c, a })
  vim.cmd("write")
  H.eq(marks.list()[1].path, c, ":w applies the new order")
  H.falsy(vim.bo[buf].modified, "...and the buffer is clean again")

  -- Deleting a pinned line asks; answer "keep it".
  local real_confirm = vim.fn.confirm
  local asked = 0
  vim.fn.confirm = function()
    asked = asked + 1
    return 3
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { c })
  vim.cmd("write")
  vim.fn.confirm = real_confirm
  H.eq(asked, 1, "removing a pinned line asks once")
  H.eq(#marks.list(), 2, "...and 'keep it' keeps it")
  H.ok(marks.index(a), "...listed still")

  -- Fix: "keep it" must sync the buffer too (append the kept path back),
  -- or the buffer still looks like the entry was removed and the SAME
  -- prompt fires again on the very next apply() -- a second :w here, with
  -- nothing else changed.
  H.eq(
    table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"),
    table.concat({ c, a }, "\n"),
    "'keep it' writes the kept path back into the buffer"
  )
  local asked_again = 0
  vim.fn.confirm = function()
    asked_again = asked_again + 1
    return 3
  end
  vim.cmd("write")
  vim.fn.confirm = real_confirm
  H.eq(asked_again, 0, "a second :w with nothing changed does not re-ask")
  H.eq(#marks.list(), 2, "...the kept entry is still there")

  menu.open_edit()
  H.falsy(menu.is_open(), "opening again toggles it closed")

  -- Deleting a non-pinned line does not ask.
  buf = menu.open_edit()
  vim.fn.confirm = function()
    asked = asked + 1
    return 3
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { a })
  vim.cmd("write")
  vim.fn.confirm = real_confirm
  H.eq(asked, 1, "a non-pinned removal is not asked about")
  H.eq(#marks.list(), 1, "...and just happens")
  menu.open_edit()

  -- the kit menu (promptless list+preview, no picker plugin needed) -------------

  config.setup({
    root = dir .. "/sroot_kit",
    branch_aware = false,
    project_aware = false,
    marks = { enable = true, defaults = { a }, import_harpoon = false, context_debounce_ms = 0 },
  })
  marks = H.fresh("sessions.marks")
  -- `defaults = { a }` only makes `a` count as pinned (see "specs and
  -- scope" above) -- it is not on the LIST until added/synced, same as the
  -- edit-menu block above.
  marks.add(a)
  marks.add(b)
  marks.update_context(b, 2, 0)

  local kit_calls = {}
  local fake_buf = vim.api.nvim_create_buf(false, true)
  package.loaded["ui.kit"] = {
    shortlist = function(opts)
      kit_calls[#kit_calls + 1] = opts
      -- A buffer of its own per call: the menu binds keys on the results buffer,
      -- and the specs below wipe every buffer between calls.
      local results_buf = vim.api.nvim_create_buf(false, true)
      return {
        close = function() end,
        current_item = function()
          return opts.items[1]
        end,
        current_index = function()
          return 1
        end,
        results = {
          bufnr = results_buf,
          winid = -1,
          is_valid = function()
            return true
          end,
        },
        preview = {
          bufnr = fake_buf,
          winid = -1,
          is_valid = function()
            return true
          end,
        },
      }
    end,
  }

  -- The stub above replaces a real module in the shared `package.loaded`
  -- table, which every later spec file in this same headless process also
  -- sees (health_spec.lua's "ui.nvim not found" branch in particular) -- so
  -- it must come back out even if an assertion below fails and unwinds this
  -- block early. `pcall` guarantees that; the outer `H.ok` re-raises so a
  -- real failure here still fails the suite.
  local kit_ok, kit_err = pcall(function()
    local menu_kit = H.fresh("sessions.marks.menu")
    menu_kit.open("kit")
    H.eq(#kit_calls, 1, 'kind = "kit" reaches ui.kit.shortlist')
    local kopts = kit_calls[1]
    H.eq(#kopts.items, 2, "one item per mark")
    H.contains(kopts.title, "Marks (", "the picker is titled with the scope")

    -- format_item: the pinned entry (a, a config default) carries the
    -- marker, the plain one (b) does not.
    local label_a, label_b
    for _, it in ipairs(kopts.items) do
      if it.path == a then
        label_a = kopts.format_item(it, 60)
      elseif it.path == b then
        label_b = kopts.format_item(it, 60)
      end
    end
    H.contains(label_a, "pin", "a pinned entry's label carries the pin marker")
    H.falsy(label_b:find("pin", 1, true), "a plain entry's label does not")

    -- render(): fills the preview surface from the real file, cursor at the
    -- remembered position.
    local rendered_lines
    local fake_surface = {
      bufnr = fake_buf,
      winid = vim.api.nvim_get_current_win(),
      set_lines = function(_, new_lines)
        rendered_lines = new_lines
      end,
      is_valid = function()
        return true
      end,
    }
    for _, it in ipairs(kopts.items) do
      if it.path == b then
        kopts.render(it, fake_surface)
      end
    end
    H.eq(rendered_lines[1], "b.lua line 1", "render() reads the real file's content")
    H.eq(
      vim.api.nvim_win_get_cursor(fake_surface.winid)[1],
      2,
      "render() places the cursor at the remembered row"
    )

    -- on_submit(): opens the file, same as the edit menu's <CR>.
    vim.cmd("silent! %bwipeout!")
    for _, it in ipairs(kopts.items) do
      if it.path == a then
        kopts.on_submit(it)
      end
    end
    H.eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), a, "on_submit opens the picked mark")

    -- on_preview_submit(): <CR> inside the preview opens the file where the
    -- preview's cursor is, not at the remembered position (b remembers row 2).
    vim.cmd("silent! %bwipeout!")
    for _, it in ipairs(kopts.items) do
      if it.path == b then
        kopts.on_preview_submit(it, 2, { row = 3, col = 0 })
      end
    end
    H.eq(
      vim.fs.normalize(vim.api.nvim_buf_get_name(0)),
      b,
      "on_preview_submit opens the previewed mark"
    )
    H.eq(
      vim.api.nvim_win_get_cursor(0)[1],
      3,
      "...at the preview cursor's row, not the remembered row 2"
    )
    -- The preview can be longer than the file (a "truncated" notice at the end):
    -- a row past the end lands on the last line instead of erroring.
    vim.cmd("silent! %bwipeout!")
    for _, it in ipairs(kopts.items) do
      if it.path == b then
        kopts.on_preview_submit(it, 2, { row = 9999, col = 40 })
      end
    end
    H.eq(vim.api.nvim_win_get_cursor(0)[1], 3, "a row past the end is clamped to the last line")

    -- marks.menu.preview_keys: nothing configured -> nothing passed, so the kit
    -- keeps its own defaults; `false` and a table go through; a wrong type is a
    -- config typo and degrades to the defaults instead of reaching the kit.
    H.eq(kopts.preview_keys, nil, "no preview_keys configured -> the kit's defaults")
    local function passed_keys(value)
      config.setup({
        root = dir .. "/sroot_kit",
        branch_aware = false,
        project_aware = false,
        marks = {
          enable = true,
          defaults = { a },
          import_harpoon = false,
          context_debounce_ms = 0,
          menu = { preview_keys = value },
        },
      })
      H.fresh("sessions.marks.menu").open("kit")
      return kit_calls[#kit_calls].preview_keys
    end
    H.eq(passed_keys(false), false, "preview_keys = false turns the keys off")
    H.ok(
      vim.deep_equal(passed_keys({ close = false }), { close = false }),
      "a table reaches the kit untouched"
    )
    H.eq(passed_keys("typo"), nil, "a value of the wrong type is dropped")
  end)
  package.loaded["ui.kit"] = nil
  H.ok(kit_ok, "the kit menu block: " .. tostring(kit_err))

  -- ui.kit unavailable: falls back to the edit menu instead of erroring.
  vim.cmd("silent! %bwipeout!")
  local menu_fallback = H.fresh("sessions.marks.menu")
  menu_fallback.open("kit")
  H.ok(menu_fallback.is_open(), 'kind = "kit" without ui.nvim falls back to the edit menu')
  menu_fallback.open_edit() -- close it again

  -- the preview -------------------------------------------------------------------

  local preview = H.fresh("sessions.marks.preview")
  marks.update_context(a, 2, 0)
  local ok_p = preview.open_index(1)
  H.ok(ok_p, "preview opens")
  H.ok(preview.is_open(), "...in a window")
  H.eq(vim.api.nvim_win_get_cursor(0)[1], 2, "...at the remembered row")
  H.eq(vim.api.nvim_get_current_line(), "line 2", "...showing the file")
  H.falsy(vim.bo.modifiable, "...read-only")
  vim.api.nvim_win_close(0, true)
  local ok_p9, err_p9 = preview.open_index(9)
  H.falsy(ok_p9, "preview past the end fails")
  H.contains(err_p9, "no mark at 9", "...")

  -- a file with NUL bytes (a binary, a UTF-16 file) ----------------------------------

  -- `readfile()` returns a NUL as "\n" inside its line, and `nvim_buf_set_lines`
  -- refuses such a line: the preview used to raise on a marked binary (and the kit
  -- pane, whose render error is swallowed, kept showing the previous file's text).
  -- The NUL shows as `^@`, the way Vim itself draws it.
  local bin = dir .. "/bin.dat"
  local bin_fh = assert(io.open(bin, "wb"))
  bin_fh:write("MZ\0\0data\nsecond\n")
  bin_fh:close()
  local bin_lines = preview.read_lines(bin)
  H.eq(bin_lines[1], "MZ^@^@data", "a NUL byte in a line shows as ^@")
  H.eq(bin_lines[2], "second", "...and a line without one is untouched")
  local scratch_buf = vim.api.nvim_create_buf(false, true)
  H.ok(
    pcall(vim.api.nvim_buf_set_lines, scratch_buf, 0, -1, false, bin_lines),
    "the lines are ones a buffer accepts"
  )
  vim.api.nvim_buf_delete(scratch_buf, { force = true })
  local ok_bin, err_bin = pcall(preview.open_path, bin, 1, 0)
  H.ok(ok_bin, "the standalone preview opens a file with NUL bytes: " .. tostring(err_bin))
  H.contains(vim.api.nvim_get_current_line(), "^@", "...and shows them as ^@")
  H.falsy(vim.bo.modifiable, "...still read-only")
  vim.api.nvim_win_close(0, true)

  -- pin_marker of the wrong type (ERR-22) ------------------------------------------

  -- `marks.menu.pin_marker` is validated by config/init.lua's validate()
  -- only as "some value" (a leaf polymorphic enough that checking its shape
  -- there would duplicate the consumer's own guard) -- so mark_pins() itself
  -- must degrade a non-string (a config typo like `pin_marker = {}`) to the
  -- built-in icon instead of erroring on the `..` it feeds into virt_text.
  config.setup({
    root = dir .. "/sroot6",
    branch_aware = false,
    project_aware = false,
    ---@diagnostic disable-next-line: assign-type-mismatch
    marks = { enable = true, defaults = { a }, import_harpoon = false, menu = { pin_marker = {} } },
  })
  H.fresh("sessions.marks")
  local menu2 = H.fresh("sessions.marks.menu")
  local ok_pm, err_pm = pcall(menu2.open_edit)
  H.ok(ok_pm, "a non-string pin_marker does not crash the edit menu: " .. tostring(err_pm))
  menu2.open_edit() -- close it again

  -- restore ---------------------------------------------------------------------

  vim.cmd("silent! %bwipeout!")
  config.setup({})
  cleanup()
end
