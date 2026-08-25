---@module 'sessions.config'
--- Holds and merges the active `Sessions.Config`, applied by `M.setup()`
--- on top of `sessions.config.DEFAULTS`.

require("sessions.@types")

---@class SessionsConfigModule
local M = {}

---@type Sessions.Config
local DEFAULTS = require("sessions.config.DEFAULTS")

---@type Sessions.Config
M.cfg = vim.deepcopy(DEFAULTS)

---@param opts table|nil
function M.setup(opts)
  M.cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {})
  M.cfg.root = require("lib.nvim.cross.fs.expand_path")(M.cfg.root)

  -- Inject Windows %TEMP% into the blacklist automatically.
  --
  -- Both spellings, and that is the whole point: on Windows $TEMP is the 8.3
  -- short form (`C:/Users/STEFAN~1/...`) for any profile name over eight
  -- characters, while a buffer opened through a resolved path -- which is what
  -- fs_realpath, an LSP or a picker hands you -- carries the long one. The
  -- blacklist is a plain prefix compare, so registering only the short form
  -- let every long-spelled temp buffer straight into the session file.
  local temp = vim.fn.expand("$TEMP")
  if temp and temp ~= "" and temp ~= "$TEMP" then
    local uv = vim.uv or vim.loop
    local spellings = { temp }
    local real = uv.fs_realpath(temp)
    if real and real ~= temp then
      spellings[#spellings + 1] = real
    end

    local candidates = {}
    for _, spelling in ipairs(spellings) do
      local win = spelling:gsub("/", "\\"):gsub("\\+$", "")
      local nix = spelling:gsub("\\", "/"):gsub("/+$", "")
      candidates[#candidates + 1] = win
      candidates[#candidates + 1] = win .. "\\"
      candidates[#candidates + 1] = nix
      candidates[#candidates + 1] = nix .. "/"
    end

    for _, candidate in ipairs(candidates) do
      local found = false
      for _, p in ipairs(M.cfg.blacklist.paths) do
        if p == candidate then
          found = true
          break
        end
      end
      if not found then
        M.cfg.blacklist.paths[#M.cfg.blacklist.paths + 1] = candidate
      end
    end
  end
end

---@return Sessions.Config
function M.get()
  return M.cfg
end

return M
