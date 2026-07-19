---@module 'sessions.DEFAULTS'

---@type Sessions.Config
return {
  root = vim.fn.stdpath("data") .. "/sessions",
  default_name = "last",
  branch_aware = true,
  project_aware = true,
  project_markers = { ".git", "pyproject.toml", "package.json", "Makefile", "Cargo.toml", "go.mod" },
  sessionoptions = "buffers,curdir,tabpages,winsize,help,folds",
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
    paths = { "/tmp/", "/private/tmp/" },
  },
  keymaps = false, -- set to a table to enable keymaps
  which_key = { enable = true },
}
