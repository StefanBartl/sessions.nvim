---@module 'sessions.bindings.keymaps'

local M = {}

---@param km Sessions.Keymaps
function M.attach(km)
  local map_ok, map = pcall(require, "lib.nvim.map")
  local set = map_ok and map or function(mode, lhs, rhs, opts)
    vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", { noremap = true, silent = true }, opts or {}))
  end

  if km.save then
    set("n", km.save, "<cmd>Session save<cr>", { desc = "Session: save" })
  end

  if km.load then
    set("n", km.load, "<cmd>Session load<cr>", { desc = "Session: load" })
  end

  if km.save_ts then
    set("n", km.save_ts, "<cmd>Session save-timestamp<cr>", { desc = "Session: save with timestamp" })
  end

  if km.list then
    set("n", km.list, "<cmd>Session list<cr>", { desc = "Session: list" })
  end
end

return M
