-- TESTS/pins_spec.lua — sessions.pins: the sidecar that carries the one
-- thing neither :mksession nor sessions.buforder does, ui.nvim's per-tabpage
-- tab-pin state (`vim.t.ui_pinned`). Modeled 1:1 on TESTS/buforder_spec.lua.
--
-- `ui.bindings.keymaps.tabufline.state` is genuinely not installed here
-- (same situation as chip_spec.lua's own note), so every path goes through
-- `H.stub`: a small fake backed by a plain `tab -> bufnrs` table, and
-- "absent entirely" to cover the soft-dependency fallback.

return function(H)
  local pins = require("sessions.pins")
  local api = vim.api

  ---@return table pins_by_tab, fun() restore
  local function stub_ui_state()
    local pins_by_tab = {}
    local restore = H.stub("ui.bindings.keymaps.tabufline.state", {
      pinned_bufs_for_tab = function(tab)
        return pins_by_tab[tab] or {}
      end,
      set_pinned_list_for_tab = function(tab, bufnrs)
        pins_by_tab[tab] = bufnrs
      end,
    })
    return pins_by_tab, restore
  end

  local dir, cleanup = H.fixture("pins")
  local session = dir .. "/work.vim"
  local sidecar = dir .. "/.work.pins.json"

  -- Real, named buffers. Compare against whatever nvim_buf_get_name reports
  -- for each (Windows may hand back a different separator than we passed in).
  local a = vim.fn.bufadd(dir .. "/a.lua")
  local b = vim.fn.bufadd(dir .. "/b.lua")
  local c = vim.fn.bufadd(dir .. "/c.lua")
  vim.fn.bufload(a)
  vim.fn.bufload(b)
  vim.fn.bufload(c)
  local name_a = vim.fs.normalize(api.nvim_buf_get_name(a))
  local name_b = vim.fs.normalize(api.nvim_buf_get_name(b))

  local cur_tab = api.nvim_get_current_tabpage()

  -- Save: pinned bufnrs round-trip to names -----------------------------------
  do
    local pins_by_tab, restore = stub_ui_state()
    pins_by_tab[cur_tab] = { a, b }
    H.ok(pins.save(session), "save reports it wrote a sidecar")
    local data = require("lib.nvim.fs.json").read(sidecar)
    H.ok(data and data.tabs and data.tabs[1], "sidecar has a tab-1 entry")
    ---@cast data -nil
    H.eq(
      table.concat(data.tabs[1], "|"),
      table.concat({ name_a, name_b }, "|"),
      "saved pins are the pinned buffers, as names"
    )
    restore()
  end

  -- Restore: resolves saved names back to live bufnrs, writes the tab's list --
  do
    local pins_by_tab, restore = stub_ui_state()
    vim.t[cur_tab].bufs = { a, b, c }
    H.ok(pins.restore(session), "restore reports it applied")
    H.eq(
      table.concat(pins_by_tab[cur_tab], "|"),
      table.concat({ a, b }, "|"),
      "the tab's pin list is the resolved saved bufnrs"
    )
    restore()
  end

  -- A saved name with no live buffer in the tab is dropped ---------------------
  do
    local pins_by_tab, restore = stub_ui_state()
    api.nvim_buf_delete(b, { force = true })
    vim.t[cur_tab].bufs = { a }
    pins.restore(session)
    H.eq(
      table.concat(pins_by_tab[cur_tab], "|"),
      tostring(a),
      "the deleted buffer is not resurrected"
    )
    restore()
  end

  -- Missing sidecar is a quiet no-op -------------------------------------------
  do
    local _, restore = stub_ui_state()
    H.falsy(pins.restore(dir .. "/never-saved.vim"), "no sidecar -> false, no error")
    restore()
  end

  -- Nothing pinned anywhere -> nothing written, stale sidecar removed ---------
  do
    local pins_by_tab, restore = stub_ui_state()
    pins_by_tab[cur_tab] = { a }
    pins.save(session) -- re-create the sidecar from the earlier block
    H.eq(vim.fn.filereadable(sidecar), 1, "sidecar present before the empty save")
    pins_by_tab[cur_tab] = {}
    H.falsy(pins.save(session), "no tab has any pin -> save writes nothing")
    H.eq(vim.fn.filereadable(sidecar), 0, "the stale sidecar was removed")
    restore()
  end

  -- Soft dependency: ui.nvim not installed -> quiet no-op, no sidecar touched --
  do
    local restore = H.stub("ui.bindings.keymaps.tabufline.state", false)
    H.falsy(pins.save(session), "no ui.nvim -> save writes nothing")
    H.eq(vim.fn.filereadable(sidecar), 0, "no sidecar left behind")
    H.falsy(pins.restore(session), "no ui.nvim -> restore applies nothing")
    restore()
  end

  -- Lifecycle: delete / rename move the sidecar with the session --------------
  do
    local pins_by_tab, restore = stub_ui_state()
    pins_by_tab[cur_tab] = { a }
    pins.save(session)
    H.eq(vim.fn.filereadable(sidecar), 1, "sidecar back")
    local renamed = dir .. "/renamed.vim"
    pins.rename(session, renamed)
    H.eq(vim.fn.filereadable(sidecar), 0, "old sidecar gone after rename")
    H.eq(vim.fn.filereadable(dir .. "/.renamed.pins.json"), 1, "new sidecar present after rename")
    pins.delete(renamed)
    H.eq(vim.fn.filereadable(dir .. "/.renamed.pins.json"), 0, "delete removes the sidecar")
    restore()
  end

  -- Full core.save -> core.load roundtrip, stubbed ui.nvim, confirming
  -- core.lua calls pins at the right moments (gated by restore_pinned_buffers,
  -- and after restore_buffer_order on load).
  do
    local pins_by_tab, restore = stub_ui_state()
    local core = require("sessions.core")
    local cfg_mod = require("sessions.config")
    cfg_mod.setup({
      root = dir .. "/sroot",
      branch_aware = false,
      project_aware = false,
      metadata = false,
      autosave = false,
    })

    -- No real tabline here (same situation as buforder_spec's own roundtrip):
    -- pins.restore() resolves saved paths against the tab's CURRENT
    -- vim.t.bufs, same as buforder.restore() does -- stand in for whatever
    -- tabline would normally maintain that list, or a reload leaves it nil
    -- and nothing has anything to resolve against.
    local aug = api.nvim_create_augroup("PinsSpecTabufline", { clear = true })
    api.nvim_create_autocmd({ "BufAdd", "BufEnter" }, {
      group = aug,
      callback = function(args)
        if vim.fn.buflisted(args.buf) == 1 and api.nvim_buf_get_name(args.buf) ~= "" then
          local tp = api.nvim_get_current_tabpage()
          local list = vim.t[tp].bufs or {}
          if not vim.tbl_contains(list, args.buf) then
            list[#list + 1] = args.buf
            vim.t[tp].bufs = list
          end
        end
      end,
    })

    local p1 = dir .. "/one.lua"
    vim.fn.writefile({ "x" }, p1)
    vim.cmd("edit " .. vim.fn.fnameescape(p1))
    local buf1 = vim.fn.bufnr(p1)

    local t = api.nvim_get_current_tabpage()
    pins_by_tab[t] = { buf1 }

    H.ok(core.save("rt"), "core.save succeeds")
    H.eq(vim.fn.filereadable(dir .. "/sroot/.rt.pins.json"), 1, "core.save wrote the pins sidecar")

    vim.cmd("silent! %bwipeout!")
    vim.t[api.nvim_get_current_tabpage()].bufs = nil
    -- Clear the table the stub writes into IN PLACE, not by rebinding this
    -- local -- `set_pinned_list_for_tab`'s closure over `pins_by_tab` (from
    -- `stub_ui_state()`) still points at the original table; reassigning
    -- this variable to a new one would silently detach this scope from what
    -- the stub actually writes to below.
    for k in pairs(pins_by_tab) do
      pins_by_tab[k] = nil
    end

    H.ok(core.load("rt"), "core.load succeeds")

    local t2 = api.nvim_get_current_tabpage()
    H.ok(pins_by_tab[t2] and #pins_by_tab[t2] == 1, "core.load reapplied the saved pin")

    api.nvim_del_augroup_by_id(aug)
    core.delete("rt") -- also clears core._current, so later specs see no session
    cfg_mod.setup({})
    restore()
  end

  cleanup()
end
