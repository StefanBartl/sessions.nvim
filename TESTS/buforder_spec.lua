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
  H.eq(table.concat(data.tabs[1], "|"), table.concat({ name_c, name_a, name_b }, "|"),
    "saved order is the reordered one, as buffer names")

  -- Restore: default order becomes the saved order ---------------------------
  vim.t[cur_tab].bufs = { a, b, c }
  H.ok(buforder.restore(session), "restore reports it applied")
  H.eq(table.concat(vim.t[cur_tab].bufs, "|"), table.concat({ c, a, b }, "|"),
    "vim.t.bufs is back in the saved order")

  -- A buffer open now but absent from the saved list is kept, appended -------
  local d = vim.fn.bufadd(dir .. "/d.lua")
  vim.fn.bufload(d)
  vim.t[cur_tab].bufs = { a, b, c, d }
  buforder.restore(session)
  H.eq(table.concat(vim.t[cur_tab].bufs, "|"), table.concat({ c, a, b, d }, "|"),
    "unsaved buffer d survives, at the end")

  -- A saved name with no live buffer is dropped -----------------------------
  api.nvim_buf_delete(c, { force = true })
  vim.t[cur_tab].bufs = { a, b }
  buforder.restore(session)
  H.eq(table.concat(vim.t[cur_tab].bufs, "|"), table.concat({ a, b }, "|"),
    "the deleted buffer is not resurrected")

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

  cleanup()
end
