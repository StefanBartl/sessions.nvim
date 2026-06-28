---@module 'sessions.config'

require("sessions.@types")

local M = {}

---@type Sessions.Config
local DEFAULTS = {
  root = vim.fn.stdpath("data") .. "/sessions",
  default_name = "last",
  branch_aware = true,
  project_aware = true,
  project_markers = { ".git", "pyproject.toml", "package.json", "Makefile", "Cargo.toml", "go.mod" },
  sessionoptions = "buffers,curdir,tabpages,winsize,help,folds",
  autoload = false,
  autosave = false,
  autosave_name = "last",
  metadata = true,
  hooks = {
    on_save = nil,
    on_load = nil,
  },
  blacklist = {
    buftypes = { "quickfix", "nofile", "prompt" },
    filetypes = { "gitcommit", "gitrebase" },
    paths = { "/tmp/", "/private/tmp/" },
  },
  keymaps = false, -- set to a table to enable keymaps
}

---@type Sessions.Config
M.cfg = vim.deepcopy(DEFAULTS)

---@param opts table|nil
function M.setup(opts)
  M.cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {})

  -- Inject Windows %TEMP% into blacklist automatically
  local temp = vim.fn.expand("$TEMP")
  if temp and temp ~= "" and temp ~= "$TEMP" then
    local norm = temp:gsub("\\", "/")
    for _, candidate in ipairs({ temp, temp .. "\\", norm, norm .. "/" }) do
      local found = false
      for _, p in ipairs(M.cfg.blacklist.paths) do
        if p == candidate then found = true; break end
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
