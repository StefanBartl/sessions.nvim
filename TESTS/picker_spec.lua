-- Test code: the captured picker options must exist by the time they are read;
-- a nil there is the failure this spec is for.
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields
-- TESTS/picker_spec.lua — sessions.picker: what `:SessionLoad` hands to a
-- picker backend, and what its actions do when they come back.
--
-- Neither snacks.nvim nor telescope.nvim is a dependency of this plugin, and
-- neither is installed in the test runtime. Both are stood up as stubs in
-- `package.loaded` -- not to simulate a picker, but because everything worth
-- testing here happens on this side of the boundary: the item list, the
-- preview text, the delete action's bookkeeping, and the fallback chain when
-- no backend is installed at all. The rendering itself is the backend's job
-- and is deliberately not covered.

return function(H)
  local picker = require("sessions.picker")
  local core = require("sessions.core")
  local config = require("sessions.config")

  local dir, cleanup = H.fixture("picker")
  vim.cmd("silent! %bwipeout!")
  config.setup({
    root = dir,
    branch_aware = false,
    project_aware = false,
    metadata = true,
    restore_buffer_order = false,
  })

  -- Notifications go through vim.notify; captured so a headless run stays
  -- quiet and so the "nothing installed" message can be asserted.
  local notified = {}
  local real_notify = vim.notify
  vim.notify = function(msg, level)
    notified[#notified + 1] = { msg = msg, level = level }
  end

  -- ------------------------------------------------------------ no sessions

  local no_snacks = H.stub("snacks", false)
  local no_telescope = H.stub("telescope", false)

  picker.pick()
  H.eq(#notified, 1, "with nothing saved, the picker says so instead of opening")
  H.contains(notified[1].msg, "no sessions saved yet", "with that message")

  -- ----------------------------------------------------- no backend installed

  H.ok(core.save("alpha"))
  H.ok(core.save("beta"))
  core.load("alpha") -- `alpha` is the current session for the rest of the spec

  notified = {}
  picker.pick()
  H.eq(#notified, 1, "with sessions but no backend, one error is reported")
  H.contains(notified[1].msg, "requires snacks.nvim", "naming what to install")
  H.eq(notified[1].level, vim.log.levels.ERROR, "as an error")

  no_snacks()
  no_telescope()

  -- --------------------------------------------------------- Snacks backend

  do
    local opts
    local restore = H.stub("snacks", {
      picker = {
        pick = function(o)
          opts = o
        end,
      },
    })

    picker.pick()
    H.ok(opts, "Snacks.picker.pick is called when snacks is installed")
    H.eq(opts.title, "Sessions", "with a title")
    H.eq(#opts.items, 2, "and one item per saved session")

    local by_name = {}
    for _, item in ipairs(opts.items) do
      by_name[item.name] = item
    end
    H.ok(by_name.alpha, "alpha is offered")
    H.ok(by_name.beta, "beta too")
    H.ok(by_name.alpha.current, "the loaded session is flagged as current")
    H.falsy(by_name.beta.current, "the other one is not")
    H.eq(by_name.alpha.text, "alpha", "the searchable text is the session name")

    -- Preview ------------------------------------------------------------
    local preview = by_name.alpha.preview.text
    H.contains(preview, "Session: alpha", "the preview names the session")
    H.contains(preview, "Saved:", "and when it was saved")
    H.contains(preview, "Cwd:", "and where from")
    H.contains(preview, "Buffers:", "and which buffers it holds")

    -- Format ---------------------------------------------------------------
    local marked = opts.format(by_name.alpha)
    H.eq(marked[1][1], "* alpha", "the current session is marked in the list")
    H.eq(marked[1][2], "SnacksPickerSpecial", "and highlighted")
    H.eq(opts.format(by_name.beta)[1][1], "  beta", "the others are indented to match")

    -- Confirm --------------------------------------------------------------
    local fake = { opts = opts, closed = false, refreshed = false }
    function fake:close()
      self.closed = true
    end
    function fake:refresh()
      self.refreshed = true
    end

    opts.confirm(fake, by_name.beta)
    H.ok(fake.closed, "confirming closes the picker")
    H.eq(core.current(), "beta", "and loads the chosen session")

    -- Confirming with nothing selected must close and do nothing else.
    fake.closed = false
    opts.confirm(fake, nil)
    H.ok(fake.closed, "confirming an empty list still closes the picker")
    H.eq(core.current(), "beta", "and loads nothing")

    -- Delete action --------------------------------------------------------
    local selection = { by_name.alpha }
    fake.selected = function()
      return selection
    end

    opts.actions.sessions_delete(fake)
    H.eq(vim.fn.filereadable(config.get().root .. "/alpha.vim"), 0, "<C-d> deletes the selection")
    H.ok(fake.refreshed, "and refreshes the picker")
    H.eq(#fake.opts.items, 1, "the deleted session is dropped from the open list")
    H.eq(fake.opts.items[1].name, "beta", "leaving the others")

    -- Nothing selected: a no-op, not a delete-everything.
    selection = {}
    fake.refreshed = false
    opts.actions.sessions_delete(fake)
    H.falsy(fake.refreshed, "deleting an empty selection does nothing at all")
    H.eq(#core.list(), 1, "and removes nothing")

    restore()
  end

  -- ------------------------------------------------------ Telescope backend

  do
    local no_snacks_again = H.stub("snacks", false)

    H.ok(core.save("gamma"))

    local built = {} ---@type table[]  # one entry per pickers.new() call
    local find_calls = 0
    local closed = {}
    local selected_entry
    local multi = {}
    local cursor_name = "gamma"

    local picker_obj = {}
    picker_obj.get_multi_selection = function()
      return multi
    end

    local restores = {}
    local function stub(name, value)
      restores[#restores + 1] = H.stub(name, value)
    end

    stub("telescope", {})
    stub("telescope.pickers", {
      new = function(_, o)
        built[#built + 1] = o
        return {
          find = function()
            find_calls = find_calls + 1
          end,
        }
      end,
    })
    stub("telescope.finders", {
      new_table = function(o)
        return o
      end,
    })
    stub("telescope.config", { values = { generic_sorter = function() end } })
    stub("telescope.actions", {
      select_default = {
        replace = function(_, fn)
          selected_entry = fn
        end,
      },
      close = function(bufnr)
        closed[#closed + 1] = bufnr
      end,
    })
    stub("telescope.actions.state", {
      get_selected_entry = function()
        return built[#built].finder.entry_maker({
          name = cursor_name,
          path = config.get().root .. "/" .. cursor_name .. ".vim",
          current = false,
        })
      end,
      get_current_picker = function()
        return picker_obj
      end,
    })
    stub("telescope.previewers", {
      new_buffer_previewer = function(o)
        return o
      end,
    })

    picker.pick()
    H.eq(#built, 1, "telescope is used when snacks is not installed")
    H.eq(find_calls, 1, "and the picker is opened")
    H.eq(built[1].prompt_title, "Sessions", "with a title")

    -- The finder's entries --------------------------------------------------
    local entries = built[1].finder.results
    H.eq(#entries, 2, "one entry per saved session")
    local entry = built[1].finder.entry_maker({ name = "beta", current = true })
    H.eq(entry.display, "* beta", "the current session is marked")
    H.eq(entry.ordinal, "beta", "and sorts under its own name")

    -- The previewer ---------------------------------------------------------
    local buf = vim.api.nvim_create_buf(false, true)
    built[1].previewer.define_preview({ state = { bufnr = buf } }, { value = entries[1] })
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    H.contains(lines[1], "Session: ", "the preview buffer is filled with the session's details")
    vim.api.nvim_buf_delete(buf, { force = true })

    -- The mappings ----------------------------------------------------------
    local mapped = {}
    local attached = built[1].attach_mappings(42, function(mode, lhs, fn)
      mapped[mode .. lhs] = fn
    end)
    H.ok(attached, "attach_mappings keeps telescope's own defaults")
    H.ok(selected_entry, "<CR> is replaced with a session load")
    H.ok(mapped["i<C-d>"], "<C-d> is mapped in insert mode")
    H.ok(mapped["n<C-d>"], "and in normal mode")

    selected_entry()
    H.eq(closed[#closed], 42, "selecting closes the prompt")
    H.eq(core.current(), "gamma", "and loads the selected session")

    -- Delete, with an explicit multi-selection.
    multi = {
      { value = { name = "beta" } },
      { value = { name = "gamma" } },
    }
    mapped["n<C-d>"]()
    H.eq(#core.list(), 0, "<C-d> deletes every multi-selected session")
    H.eq(#built, 2, "and reopens the picker on the shortened list")

    -- With nothing multi-selected it falls back to the entry under the cursor,
    -- which `get_selected_entry` above always answers.
    multi = {}
    cursor_name = "delta"
    H.ok(core.save("delta"))
    mapped["n<C-d>"]()
    H.eq(#built, 3, "with no multi-selection the picker reopens too")
    H.eq(#core.list(), 0, "having deleted the entry under the cursor")

    for _, undo in ipairs(restores) do
      undo()
    end
    no_snacks_again()
  end

  -- Leave nothing behind ------------------------------------------------------
  for _, p in ipairs(core.list()) do
    core.delete(vim.fn.fnamemodify(p, ":t:r"))
  end
  H.falsy(core.current(), "no session stays active")

  vim.notify = real_notify
  config.setup({})
  vim.cmd("silent! %bwipeout!")
  cleanup()
end
