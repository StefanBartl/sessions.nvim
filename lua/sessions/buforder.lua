---@module 'sessions.buforder'
--- Persist and restore per-tabpage buffer *ordering* — the one piece of tab
--- state `:mksession` cannot carry.
---
--- NvChad's tabufline (and any tabline that keeps an ordered `vim.t.bufs`
--- list of buffer numbers) renders its bar straight from that list. The
--- "move tab left/right" keymaps only reorder `vim.t.bufs`; `:mksession`
--- serializes buffers, windows and tabpages but never a tab-local variable,
--- so after a save + load the bar comes back in default buffer order and the
--- manual reordering looks like it never happened.
---
--- This module writes the ordering to a hidden `.{name}.bufs.json` sidecar
--- next to the session file (same convention as `sessions.meta`) and
--- reapplies it after `:source`.
---
--- It is a no-op — and writes no sidecar — when no tabpage carries a
--- `vim.t.bufs` list, so a setup without such a tabline pays nothing.

require("sessions.@types")

local api = vim.api
local fn = vim.fn

---@class SessionsBuforder
local M = {}

---@internal
---@param session_path string
---@return string
local function sidecar_path(session_path)
  local dir = fn.fnamemodify(session_path, ":h")
  local base = fn.fnamemodify(session_path, ":t:r")
  return dir .. "/." .. base .. ".bufs.json"
end

---@internal
---Read `vim.t[tab].bufs` and map it to an ordered list of buffer *names*
---(absolute paths). Returns nil when the tabpage has no `vim.t.bufs`.
---@param tab integer  tabpage handle
---@return string[]|nil
local function tab_buf_names(tab)
  local ok, bufs = pcall(function()
    return vim.t[tab].bufs
  end)
  if not ok or type(bufs) ~= "table" then
    return nil
  end
  local names = {}
  for _, b in ipairs(bufs) do
    if type(b) == "number" and api.nvim_buf_is_valid(b) then
      local nm = api.nvim_buf_get_name(b)
      if nm ~= "" then
        -- Normalized so the match at restore survives `:mksession` rewriting
        -- the same path with different separators / a `~` prefix.
        names[#names + 1] = vim.fs.normalize(nm)
      end
    end
  end
  return names
end

---Capture every tabpage's `vim.t.bufs` ordering into the sidecar for
---`session_path`. Removes any stale sidecar and returns `false` when no
---tabpage carries a `vim.t.bufs` list.
---@param session_path string
---@return boolean wrote
function M.save(session_path)
  local tabs = {}
  local any = false
  for i, tab in ipairs(api.nvim_list_tabpages()) do
    local names = tab_buf_names(tab)
    if names and #names > 0 then
      any = true
      tabs[i] = names
    else
      tabs[i] = {}
    end
  end

  local path = sidecar_path(session_path)
  if not any then
    os.remove(path)
    return false
  end

  local ok = require("lib.nvim.fs.json").write(path, { tabs = tabs })
  return ok == true
end

---Reapply the saved per-tabpage buffer ordering for `session_path`.
---
---Only touches a tabpage that still carries a `vim.t.bufs` list. A buffer
---open in the tab now but absent from the saved order is kept, appended in
---its current position; a saved name with no live buffer is dropped. Ends
---with `:redrawtabline` so the bar repaints in the new order.
---@param session_path string
---@return boolean applied
function M.restore(session_path)
  local data = require("lib.nvim.fs.json").read(sidecar_path(session_path))
  if type(data) ~= "table" or type(data.tabs) ~= "table" then
    return false
  end

  local applied = false
  for i, tab in ipairs(api.nvim_list_tabpages()) do
    local saved = data.tabs[i]
    local ok, current = pcall(function()
      return vim.t[tab].bufs
    end)
    if ok and type(current) == "table" and type(saved) == "table" and #saved > 0 then
      local by_name = {}
      for _, b in ipairs(current) do
        if type(b) == "number" and api.nvim_buf_is_valid(b) then
          local nm = api.nvim_buf_get_name(b)
          if nm ~= "" then
            by_name[vim.fs.normalize(nm)] = b
          end
        end
      end

      local ordered, placed = {}, {}
      for _, nm in ipairs(saved) do
        local b = by_name[vim.fs.normalize(nm)]
        if b and not placed[b] then
          ordered[#ordered + 1] = b
          placed[b] = true
        end
      end
      for _, b in ipairs(current) do
        if type(b) == "number" and not placed[b] and api.nvim_buf_is_valid(b) then
          ordered[#ordered + 1] = b
          placed[b] = true
        end
      end

      if #ordered > 0 then
        vim.t[tab].bufs = ordered
        applied = true
      end
    end
  end

  if applied then
    pcall(vim.cmd, "redrawtabline")
  end
  return applied
end

---Remove the sidecar for `session_path` (session deleted).
---@param session_path string
function M.delete(session_path)
  os.remove(sidecar_path(session_path))
end

---Move the sidecar alongside a renamed session file.
---@param old_path string
---@param new_path string
function M.rename(old_path, new_path)
  local old = sidecar_path(old_path)
  local content = require("lib.nvim.fs.read")(old)
  if not content then
    return
  end
  if require("lib.nvim.fs.write.to_file")(sidecar_path(new_path), content) then
    os.remove(old)
  end
end

return M
