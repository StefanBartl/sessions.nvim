---@module 'sessions.util.sidecar'
---@brief The one write path for the JSON sidecars next to a session file.
---@description
--- `sessions.meta`, `sessions.buforder` and `sessions.pins` each keep a hidden
--- `.<name>[.<kind>].json` beside the session file. All three write it the
--- same way, and all three have to handle a failed write the same way: the
--- reason goes back to the caller (`sessions.core` reports it), and a sidecar
--- left over from an EARLIER save is removed. Without that removal the next
--- load would apply the previous save's order / pins / metadata to the new
--- session file as if they belonged to it.

local M = {}

---Write `data` as JSON to the sidecar at `path`. On failure the stale
---sidecar at `path` (from an earlier save) is removed, best effort -- a
---target that is locked or unreachable stays, there is nothing else to do.
---@param path string  Absolute sidecar path
---@param data table
---@return boolean ok
---@return string|nil err  `"<path>: <reason>"` when the write failed
function M.write(path, data)
  local ok, err = require("lib.nvim.fs.json").write(path, data)
  if ok then
    return true, nil
  end
  os.remove(path)
  return false, path .. ": " .. tostring(err)
end

return M
