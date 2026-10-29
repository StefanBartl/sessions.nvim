-- TESTS/keymaps_press_spec.lua — the mark-list keymaps, pressed for real.
--
-- keymaps_spec asserts what is declared and what lands in Neovim's mapping
-- table; this one presses every key and checks what it did. The table below is
-- the one the reference host config binds (`<leader>h*`, plus the numbered
-- jumps from `marks.select_key = "<leader>h%d"`), attached through the same
-- public `keymaps.attach()` it calls.
--
-- Keys go through `nvim_feedkeys(..., "mx")`: remapped like typed input, and
-- the typeahead is executed before the call returns, so each `<cmd>` mapping
-- has run by the next line. The effect is then read back through the
-- `sessions.marks` API, the current buffer, or the notifications.
--
-- Everything lives under a TESTS/.fixture-* directory: the session root (and
-- with it the mark store and the pins), the marked files. The real
-- `stdpath("data")` is never read -- the harpoon import is off.

return function(H)
  local config = require("sessions.config")

  local dir, cleanup = H.fixture("keymaps-press")
  vim.cmd("silent! %bwipeout!")

  ---@param name string
  ---@return string
  local function file(name)
    local p = dir .. "/" .. name
    vim.fn.writefile({ name .. " line 1", "line 2", "line 3" }, p)
    return vim.fs.normalize(p)
  end
  local files = {}
  for i = 1, 9 do
    files[i] = file(("m%d.txt"):format(i))
  end
  local dflt = file("default.md")

  config.setup({
    root = dir .. "/sroot",
    branch_aware = false,
    project_aware = false,
    marks = {
      enable = true,
      scope = "global",
      defaults = { dflt },
      import_harpoon = false,
      context_debounce_ms = 0,
      select_key = "<leader>h%d",
    },
  })

  -- Notifications are what `:Session marks select` and `defaults sync` report
  -- through; the notifier is cached at module load, so the recorder goes in
  -- before the modules are required.
  local said = {} ---@type string[]
  local restore_notify = H.stub("lib.nvim.notify", {
    create = function()
      local rec = {}
      for _, level in ipairs({ "info", "warn", "error" }) do
        rec[level] = function(msg)
          said[#said + 1] = level .. ": " .. tostring(msg)
        end
      end
      return rec
    end,
  })

  local marks = H.fresh("sessions.marks")
  local menu = H.fresh("sessions.marks.menu")
  H.fresh("sessions.bindings.usercmds").enable()

  vim.g.mapleader = " "
  local keymaps = H.fresh("sessions.bindings.keymaps")
  keymaps.attach({
    marks_menu = "<leader>hm",
    marks_edit = "<leader>hE",
    marks_add = "<leader>ha",
    marks_add_front = "<leader>hA",
    marks_pin = "<leader>hp",
    marks_remove = "<leader>hd",
    marks_sync = "<leader>hs",
    marks_debug = "<leader>hD",
  }, false)

  ---Type `keys` as if from the keyboard and run them to completion.
  ---@param keys string
  local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
  end

  ---@return string
  local function current()
    return vim.fs.normalize(vim.api.nvim_buf_get_name(0))
  end

  ---@return string[]
  local function paths()
    local out = {}
    for i, it in ipairs(marks.list()) do
      out[i] = it.path
    end
    return out
  end

  ---@param path string
  local function edit(path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end

  local body_ok, body_err = pcall(function()
    -- <leader>ha: mark this file -- appended, in the order pressed ------------
    H.eq(#marks.list(), 0, "the store starts empty")
    for i = 1, 9 do
      edit(files[i])
      press("<leader>ha")
      H.eq(marks.index(files[i]), i, ("<leader>ha appends m%d at slot %d"):format(i, i))
    end
    edit(files[3])
    press("<leader>ha")
    H.eq(#marks.list(), 9, "<leader>ha on a listed file does not add it twice")
    H.eq(marks.index(files[3]), 3, "and leaves it where it was")

    -- <leader>hA: mark this file first -- moves a listed file to slot 1 -------
    edit(files[5])
    press("<leader>hA")
    H.eq(marks.index(files[5]), 1, "<leader>hA moves the current file to slot 1")
    H.eq(#marks.list(), 9, "without duplicating it")
    H.eq(marks.index(files[1]), 2, "the rest shifts down by one")

    -- <leader>h1..9: jump to mark N, at its remembered position ---------------
    local order = paths()
    marks.update_context(order[4], 3, 2)
    for n = 1, 9 do
      vim.cmd("enew")
      press("<leader>h" .. n)
      H.eq(current(), order[n], ("<leader>h%d opens mark %d"):format(n, n))
    end
    vim.cmd("enew")
    press("<leader>h4")
    H.eq(vim.api.nvim_win_get_cursor(0)[1], 3, "the jump lands on the remembered row")
    H.eq(vim.api.nvim_win_get_cursor(0)[2], 2, "and column")

    -- <leader>hd: unmark this file --------------------------------------------
    edit(order[9])
    press("<leader>hd")
    H.eq(marks.index(order[9]), nil, "<leader>hd removes the current file")
    H.eq(#marks.list(), 8, "and only that one")

    -- A jump past the end now reports instead of opening anything.
    vim.cmd("enew")
    local before = #said
    press("<leader>h9")
    H.eq(current(), "", "<leader>h9 with eight marks stays in the empty buffer")
    H.ok(#said > before, "and says why")
    H.contains(said[#said], "no mark at 9", "naming the missing slot")

    -- <leader>hp: pin this file -- a runtime default, put first ---------------
    edit(order[9])
    press("<leader>hp")
    H.eq(marks.index(order[9]), 1, "<leader>hp puts the current file at slot 1")
    H.ok(marks.is_pinned(order[9]), "and records it as a pin")

    -- <leader>hs: add missing default marks -----------------------------------
    marks.remove(order[9])
    H.eq(marks.index(dflt), nil, "the config default is not listed yet")
    H.eq(marks.index(order[9]), nil, "nor is the removed pin")
    press("<leader>hs")
    H.ok(marks.index(dflt), "<leader>hs adds the config default")
    H.ok(marks.index(order[9]), "and the pin that was removed")
    H.contains(said[#said], "2 default(s) added", "and reports how many")
    local synced = #marks.list()
    press("<leader>hs")
    H.eq(#marks.list(), synced, "a second <leader>hs adds nothing")

    -- <leader>hD: dump the mark list into a scratch buffer --------------------
    local wins = #vim.api.nvim_tabpage_list_wins(0)
    press("<leader>hD")
    H.eq(#vim.api.nvim_tabpage_list_wins(0), wins + 1, "<leader>hD opens a split")
    H.eq(vim.bo.buftype, "nofile", "holding a scratch buffer")
    local dump = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    H.contains(dump, ("items: %d"):format(synced), "that counts the marks")
    H.contains(dump, marks.store_path(), "and names the fixture store")
    vim.cmd("close")

    -- <leader>hE: the editable list, toggled ----------------------------------
    press("<leader>hE")
    H.ok(menu.is_open(), "<leader>hE opens the edit menu")
    H.eq(vim.bo.filetype, "sessions-marks", "and focuses its buffer")
    H.eq(
      table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"),
      table.concat(paths(), "\n"),
      "which lists every mark, in order"
    )
    press("<leader>hE")
    H.falsy(menu.is_open(), "a second <leader>hE closes it")

    -- <leader>hm: the picker (ui.kit, recorded) -------------------------------
    local kit_calls = {}
    local restore_kit = H.stub("ui.kit", {
      shortlist = function(opts)
        kit_calls[#kit_calls + 1] = opts
        local buf = vim.api.nvim_create_buf(false, true)
        local surface = {
          bufnr = buf,
          winid = -1,
          is_valid = function()
            return true
          end,
        }
        return {
          close = function() end,
          current_item = function()
            return opts.items[1]
          end,
          current_index = function()
            return 1
          end,
          results = surface,
          preview = surface,
        }
      end,
    })
    local kit_ok, kit_err = pcall(function()
      press("<leader>hm")
      H.eq(#kit_calls, 1, "<leader>hm opens the marks picker")
      H.eq(#kit_calls[1].items, synced, "with one item per mark")
    end)
    restore_kit()
    H.ok(kit_ok, "the picker block: " .. tostring(kit_err))
  end)

  vim.cmd("silent! %bwipeout!")
  for _, lhs in ipairs({ "ha", "hA", "hd", "hp", "hs", "hD", "hE", "hm" }) do
    pcall(vim.keymap.del, "n", "<leader>" .. lhs)
  end
  for i = 1, 9 do
    pcall(vim.keymap.del, "n", "<leader>h" .. i)
  end
  restore_notify()
  cleanup()
  H.ok(body_ok, tostring(body_err))
end
