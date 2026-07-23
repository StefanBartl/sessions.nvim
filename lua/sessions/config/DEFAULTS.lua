---@module 'sessions.DEFAULTS'

---Default blacklisted path prefixes for the current OS. Windows' actual
---%TEMP% value is re-checked and appended at runtime too (see config/init.lua),
---since it varies per machine/user — this just avoids a Unix-only default
---on a fresh Windows install before setup() runs.
---@return string[]
local function default_blacklist_paths()
  if vim.fn.has("win32") == 1 then
    local temp = vim.fn.expand("$TEMP"):gsub("\\", "/")
    return { temp .. "/", temp .. "\\" }
  end
  return { "/tmp/", "/private/tmp/" }
end

---@type Sessions.Config
return {
  root = vim.fn.stdpath("data") .. "/sessions",
  default_name = "last",
  branch_aware = true,
  project_aware = true,
  project_markers = { ".git", "pyproject.toml", "package.json", "Makefile", "Cargo.toml", "go.mod" },
  sessionoptions = "buffers,curdir,tabpages,winsize,help,folds",
  relative_paths = false,
  root_remap = {},
  autoload = false,
  autosave = true,
  autosave_name = "last",
  metadata = true,
  hooks = {
    on_save = nil,
    on_load = nil,
  },
  blacklist = {
    buftypes = { "quickfix", "nofile", "prompt" },
    filetypes = { "gitcommit", "gitrebase" },
    paths = default_blacklist_paths(),
  },
  keymaps = false, -- set to a table to enable keymaps
  which_key = { enable = true },
}
