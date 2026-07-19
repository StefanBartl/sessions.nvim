---@module 'sessions.which_key'
---@brief Optional, guarded which-key group label for the session keymaps.
---@description
--- which-key is a **soft** dependency: if it is not installed this is a no-op.
--- Individual keys already carry their own `desc` (see keymaps.lua), so only
--- a group label for the shared "<leader>s" prefix is registered. Supports
--- both the which-key v3 (`add`) and v2 (`register`) APIs.

local M = {}

---Register the sessions.nvim group label with which-key, if available.
---@param km Sessions.Keymaps
---@return boolean registered
function M.setup(km)
  local ok, wk = pcall(require, "which-key")
  if not ok or type(wk) ~= "table" then
    return false
  end

  -- Find the longest common prefix across the configured keymaps so the
  -- group label doesn't clobber unrelated "<leader>s..." mappings from
  -- other plugins if the user picked a wider shared prefix on purpose.
  local lhs_list = {}
  for _, lhs in pairs(km) do
    if type(lhs) == "string" and lhs ~= "" then
      lhs_list[#lhs_list + 1] = lhs
    end
  end
  if #lhs_list == 0 then
    return false
  end

  local prefix = lhs_list[1]:sub(1, -2)
  for _, lhs in ipairs(lhs_list) do
    while prefix ~= "" and lhs:sub(1, #prefix) ~= prefix do
      prefix = prefix:sub(1, -2)
    end
  end
  if prefix == "" then
    return false
  end

  if type(wk.add) == "function" then
    -- which-key v3
    wk.add({ { prefix, group = "Session" } })
    return true
  elseif type(wk.register) == "function" then
    -- which-key v2
    wk.register({ [prefix] = { name = "+Session" } })
    return true
  end

  return false
end

---Whether which-key is installed (for :checkhealth reporting).
---@return boolean
function M.available()
  local ok, wk = pcall(require, "which-key")
  return ok and type(wk) == "table"
end

return M
