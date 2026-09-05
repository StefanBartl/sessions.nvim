-- TESTS/buforder_spec.lua — sessions.buforder: the sidecar that carries the
-- one thing :mksession cannot, a tabline's per-tabpage `vim.t.bufs` ordering
-- (NvChad's tabufline and anything shaped like it). No NvChad here — the test
-- drives `vim.t.bufs` directly, which is exactly the surface the module reads
-- and writes.

return function(H)
  local buforder = require("sessions.buforder")
  local api = vim.api

  local dir, cleanup = H.fixture("buforder")
  local session = dir .. "/work.vim"
  local sidecar = dir .. "/.work.bufs.json"

  -- Real, named buffers. Compare against whatever nvim_buf_get_name reports
  -- for each (Windows may hand back a different separator than we passed in).
  local a = vim.fn.bufadd(dir .. "/a.lua")
  local b = vim.fn.bufadd(dir .. "/b.lua")
  local c = vim.fn.bufadd(dir .. "/c.lua")
  vim.fn.bufload(a)
  vim.fn.bufload(b)
  vim.fn.bufload(c)
  -- buforder normalizes names before it stores them (separator / `~`), so the
  -- expectations here do the same.
  local name_a = vim.fs.normalize(api.nvim_buf_get_name(a))
  local name_b = vim.fs.normalize(api.nvim_buf_get_name(b))
  local name_c = vim.fs.normalize(api.nvim_buf_get_name(c))

  local cur_tab = api.nvim_get_current_tabpage()

  -- Save: a hand-reordered list round-trips to names, in order -----------------
  vim.t[cur_tab].bufs = { c, a, b }
  H.ok(buforder.save(session), "save reports it wrote a sidecar")
  local data = require("lib.nvim.fs.json").read(sidecar)
  H.ok(data and data.tabs and data.tabs[1], "sidecar has a tab-1 entry")
  ---@cast data -nil
  H.eq(
    table.concat(data.tabs[1], "|"),
    table.concat({ name_c, name_a, name_b }, "|"),
    "saved order is the reordered one, as buffer names"
  )

  -- Restore: default order becomes the saved order ---------------------------
  vim.t[cur_tab].bufs = { a, b, c }
  H.ok(buforder.restore(session), "restore reports it applied")
  H.eq(
    table.concat(vim.t[cur_tab].bufs, "|"),
    table.concat({ c, a, b }, "|"),
    "vim.t.bufs is back in the saved order"
  )

  -- A buffer open now but absent from the saved list is kept, appended -------
  local d = vim.fn.bufadd(dir .. "/d.lua")
  vim.fn.bufload(d)
  vim.t[cur_tab].bufs = { a, b, c, d }
  buforder.restore(session)
  H.eq(
    table.concat(vim.t[cur_tab].bufs, "|"),
    table.concat({ c, a, b, d }, "|"),
    "unsaved buffer d survives, at the end"
  )

  -- A saved name with no live buffer is dropped -----------------------------
  api.nvim_buf_delete(c, { force = true })
  vim.t[cur_tab].bufs = { a, b }
  buforder.restore(session)
  H.eq(
    table.concat(vim.t[cur_tab].bufs, "|"),
    table.concat({ a, b }, "|"),
    "the deleted buffer is not resurrected"
  )

  -- Missing sidecar is a quiet no-op --------------------------------------
  H.falsy(buforder.restore(dir .. "/never-saved.vim"), "no sidecar -> false, no error")

  -- No `vim.t.bufs` anywhere -> nothing written, stale sidecar removed ------
  vim.t[cur_tab].bufs = nil
  H.falsy(buforder.save(session), "no tab has vim.t.bufs -> save writes nothing")
  H.eq(vim.fn.filereadable(sidecar), 0, "the stale sidecar was removed")

  -- Lifecycle: delete / rename move the sidecar with the session -----------
  vim.t[cur_tab].bufs = { a, b }
  buforder.save(session)
  H.eq(vim.fn.filereadable(sidecar), 1, "sidecar back")
  local renamed = dir .. "/renamed.vim"
  buforder.rename(session, renamed)
  H.eq(vim.fn.filereadable(sidecar), 0, "old sidecar gone after rename")
  H.eq(vim.fn.filereadable(dir .. "/.renamed.bufs.json"), 1, "new sidecar present after rename")
  buforder.delete(renamed)
  H.eq(vim.fn.filereadable(dir .. "/.renamed.bufs.json"), 0, "delete removes the sidecar")

  -- Full core.save -> core.load roundtrip through the real session pipeline,
  -- with a stand-in for NvChad's `vim.t.bufs`-maintaining autocmd. (The module
  -- is validated against the real tabufline separately; the point here is that
  -- core.lua calls buforder at the right moments.)
  do
    local core = require("sessions.core")
    local cfg_mod = require("sessions.config")
    cfg_mod.setup({
      root = dir .. "/sroot",
      branch_aware = false,
      project_aware = false,
      metadata = false,
      autosave = false,
    })

    local aug = api.nvim_create_augroup("BuforderSpecTabufline", { clear = true })
    api.nvim_create_autocmd({ "BufAdd", "BufEnter" }, {
      group = aug,
      callback = function(args)
        if vim.fn.buflisted(args.buf) == 1 and api.nvim_buf_get_name(args.buf) ~= "" then
          local t = api.nvim_get_current_tabpage()
          local list = vim.t[t].bufs or {}
          if not vim.tbl_contains(list, args.buf) then
            list[#list + 1] = args.buf
            vim.t[t].bufs = list
          end
        end
      end,
    })

    local p1, p2, p3 = dir .. "/one.lua", dir .. "/two.lua", dir .. "/three.lua"
    for _, p in ipairs({ p1, p2, p3 }) do
      vim.fn.writefile({ "x" }, p)
      vim.cmd("edit " .. vim.fn.fnameescape(p))
    end

    local t = api.nvim_get_current_tabpage()
    vim.t[t].bufs = { vim.fn.bufnr(p3), vim.fn.bufnr(p1), vim.fn.bufnr(p2) } -- hand reorder

    H.ok(core.save("rt"), "core.save succeeds")
    H.eq(
      vim.fn.filereadable(dir .. "/sroot/.rt.bufs.json"),
      1,
      "core.save wrote the buforder sidecar"
    )

    vim.cmd("silent! %bwipeout!")
    vim.t[api.nvim_get_current_tabpage()].bufs = nil

    H.ok(core.load("rt"), "core.load succeeds")

    local t2 = api.nvim_get_current_tabpage()
    local restored = vim.tbl_map(function(x)
      return vim.fn.fnamemodify(api.nvim_buf_get_name(x), ":t")
    end, vim.t[t2].bufs or {})
    H.eq(
      table.concat(restored, "|"),
      "three.lua|one.lua|two.lua",
      "core.load reapplied the saved vim.t.bufs order"
    )

    api.nvim_del_augroup_by_id(aug)
    core.delete("rt") -- also clears core._current, so later specs see no session
    cfg_mod.setup({})
  end

  cleanup()
end
