---@module 'sessions.pins'
--- Persist and restore per-tabpage tab-pin state (`ui.nvim`'s tabline
--- pinned-buffer list) -- the one piece of tab state neither `:mksession`
--- nor `sessions.buforder` carries.
---
--- `ui.nvim`'s `ui.bindings.keymaps.tabufline.state` module keeps
--- `vim.t.ui_pinned`, a tab-local list of pinned bufnrs, but explicitly does
--- not persist it across a restart (see that module's own doc comment). This
--- writes it to a hidden `.{name}.pins.json` sidecar next to the session
--- file (same convention as `sessions.buforder`, and `sessions.meta` before
--- both) and reapplies it after `:source`.
---
--- Soft dependency on `ui.nvim`: a no-op, no sidecar written or read, when
--- `ui.bindings.keymaps.tabufline.state` is not on `runtimepath` -- same
--- pattern as `sessions.chip`'s own soft dependency on `ui.kit`.
---
--- `M.restore()` must run AFTER `sessions.buforder.restore()`: that call is
--- what settles the final, stable bufnr<->path mapping for a tab (a buffer
--- open now but absent from the saved order is appended, kept), and pin
--- restore needs that final mapping, not whatever `:mksession` alone left
--- `vim.t.bufs` as.

require("sessions.@types")

local api = vim.api
local fn = vim.fn

---@class SessionsPins
local M = {}

---@internal
---@return table|nil state  `ui.bindings.keymaps.tabufline.state`, when ui.nvim is installed
local function tabufline_state()
  local ok, mod = pcall(require, "ui.bindings.keymaps.tabufline.state")
  if ok then
    return mod
  end
  return nil
end

---@internal
---@param session_path string
---@return string
local function sidecar_path(session_path)
  local dir = fn.fnamemodify(session_path, ":h")
  local base = fn.fnamemodify(session_path, ":t:r")
  return dir .. "/." .. base .. ".pins.json"
end

---@internal
---`tab`'s pinned bufnrs mapped to absolute paths -- only a valid, named
---buffer can round-trip through the sidecar. Returns nil when `state`
---reports no pins for `tab` at all (as opposed to an empty list -- both
---result in nothing to save, callers only need to tell "no data" from
---"data present").
---@param state table
---@param tab integer
---@return string[]|nil
local function tab_pin_names(state, tab)
  local ok, pinned = pcall(state.pinned_bufs_for_tab, tab)
  if not ok or type(pinned) ~= "table" then
    return nil
  end
  local names = {}
  for _, b in ipairs(pinned) do
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

---Capture every tabpage's pinned-buffer paths into the sidecar for
---`session_path`. Removes any stale sidecar and returns `false` when
---`ui.nvim` is not installed or no tabpage has anything pinned.
---@param session_path string
---@return boolean wrote
function M.save(session_path)
  local path = sidecar_path(session_path)
  local state = tabufline_state()
  if not state then
    os.remove(path)
    return false
  end

  local tabs = {}
  local any = false
  for i, tab in ipairs(api.nvim_list_tabpages()) do
    local names = tab_pin_names(state, tab)
    if names and #names > 0 then
      any = true
      tabs[i] = names
    else
      tabs[i] = {}
    end
  end

  if not any then
    os.remove(path)
    return false
  end

  local ok = require("lib.nvim.fs.json").write(path, { tabs = tabs })
  return ok == true
end

---Reapply the saved per-tabpage pin state for `session_path`. A no-op when
---`ui.nvim` is not installed or no sidecar exists. Resolves each saved path
---back to a live bufnr by name against the tab's CURRENT `vim.t.bufs` (i.e.
---after `sessions.buforder.restore()` has already settled it) the same way
---`sessions.buforder.restore` resolves its own saved order, dropping any
---path no longer open in that tab.
---@param session_path string
---@return boolean applied
function M.restore(session_path)
  local state = tabufline_state()
  if not state then
    return false
  end

  local data = require("lib.nvim.fs.json").read(sidecar_path(session_path))
  if type(data) ~= "table" or type(data.tabs) ~= "table" then
    return false
  end

  local applied = false
  for i, tab in ipairs(api.nvim_list_tabpages()) do
    local saved = data.tabs[i]
    if type(saved) == "table" and #saved > 0 then
      local ok, current = pcall(function()
        return vim.t[tab].bufs
      end)
      if ok and type(current) == "table" then
        local by_name = {}
        for _, b in ipairs(current) do
          if type(b) == "number" and api.nvim_buf_is_valid(b) then
            local nm = api.nvim_buf_get_name(b)
            if nm ~= "" then
              by_name[vim.fs.normalize(nm)] = b
            end
          end
        end

        local resolved, placed = {}, {}
        for _, nm in ipairs(saved) do
          local b = by_name[vim.fs.normalize(nm)]
          if b and not placed[b] then
            resolved[#resolved + 1] = b
            placed[b] = true
          end
        end

        if #resolved > 0 then
          state.set_pinned_list_for_tab(tab, resolved)
          applied = true
        end
      end
    end
  end

  if applied then
    pcall(function()
      vim.cmd("redrawtabline")
    end)
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
