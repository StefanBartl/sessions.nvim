---@module 'sessions.health'

local M = {}

function M.check()
  vim.health.start("sessions.nvim")

  -- Neovim version
  if vim.fn.has("nvim-0.9") == 1 then
    vim.health.ok("Neovim >= 0.9")
  else
    vim.health.error("Neovim 0.9+ required (vim.health API)")
  end

  -- vim.json (used for metadata)
  if vim.json and vim.json.encode then
    vim.health.ok("vim.json available (metadata enabled)")
  else
    vim.health.warn("vim.json unavailable — metadata will be disabled")
  end

  -- libuv
  if vim.uv or vim.loop then
    vim.health.ok("libuv available (" .. (vim.uv and "vim.uv" or "vim.loop") .. ")")
  else
    vim.health.warn("libuv not found")
  end

  -- vim.system (Neovim 0.10+, used for git operations)
  if vim.system then
    vim.health.ok("vim.system available (Neovim 0.10+)")
  else
    vim.health.info("vim.system unavailable — git ops fall back to vim.fn.system")
  end

  -- setup called
  if vim.g.loaded_sessions_nvim then
    vim.health.ok("plugin loaded (setup() called)")
  else
    vim.health.warn("plugin not loaded — call require('sessions').setup()")
  end

  -- lib.nvim: required for the :Session/:LastSession commands (built on
  -- lib.nvim.usercmd.composer); notify/map/git submodules stay soft-guarded.
  vim.health.start("sessions.nvim — lib.nvim")

  local lib_composer_ok = pcall(require, "lib.nvim.usercmd.composer")
  if lib_composer_ok then
    vim.health.ok("lib.nvim found — :Session/:LastSession available")
  else
    vim.health.error('lib.nvim not found — :Session/:LastSession will fail to load; install "StefanBartl/lib.nvim"')
  end

  local lib_notify_ok = pcall(require, "lib.nvim.notify")
  if lib_notify_ok then
    vim.health.ok("lib.nvim.notify available (enhanced notifications)")
  else
    vim.health.info("lib.nvim.notify not found — using vim.notify fallback")
  end

  local lib_map_ok = pcall(require, "lib.nvim.map")
  if lib_map_ok then
    vim.health.ok("lib.nvim.map available (enhanced keymaps)")
  else
    vim.health.info("lib.nvim.map not found — using vim.keymap.set fallback")
  end

  local lib_git_ok = pcall(require, "lib.nvim.git")
  if lib_git_ok then
    vim.health.ok("lib.nvim.git available (branch detection)")
  else
    vim.health.info("lib.nvim.git not found — using git CLI fallback")
  end

  if require("sessions.bindings.which_key").available() then
    vim.health.ok("which-key available (keymap group label registered)")
  else
    vim.health.info("which-key not found (optional; keymap `desc` fields still work standalone)")
  end

  -- configuration
  vim.health.start("sessions.nvim — configuration")

  local cfg_ok, cfg_mod = pcall(require, "sessions.config")
  if not cfg_ok then
    vim.health.error("sessions.config failed to load")
    return
  end

  local cfg = cfg_mod.get()

  vim.health.info("root: " .. cfg.root)
  vim.health.info("default_name: " .. cfg.default_name)
  vim.health.info("branch_aware: " .. tostring(cfg.branch_aware))
  vim.health.info("project_aware: " .. tostring(cfg.project_aware))
  vim.health.info("autoload: " .. tostring(cfg.autoload))
  vim.health.info("autosave: " .. tostring(cfg.autosave))
  vim.health.info("metadata: " .. tostring(cfg.metadata))

  -- Check root accessibility
  local uv = vim.uv or vim.loop
  local st = uv.fs_stat(cfg.root)
  if st and st.type == "directory" then
    vim.health.ok("session root exists: " .. cfg.root)
    local sessions = require("sessions.core").list()
    vim.health.info(("%d session(s) stored"):format(#sessions))
  else
    vim.health.info("session root does not exist yet (will be created on first save): " .. cfg.root)
  end

  -- sessionoptions sanity
  local opts = cfg.sessionoptions
  if opts and opts ~= "" then
    vim.health.ok("sessionoptions: " .. opts)
  else
    vim.health.warn("sessionoptions is empty")
  end

  -- commands
  vim.health.start("sessions.nvim — commands")
  if vim.fn.exists(":Session") == 2 then
    vim.health.ok(":Session registered (save, save-timestamp, load, delete, rename, list, current, toggle-track)")
  else
    vim.health.warn(":Session not found — call setup() first")
  end
  if vim.fn.exists(":LastSession") == 2 then
    vim.health.ok(":LastSession registered")
  else
    vim.health.warn(":LastSession not found — call setup() first")
  end
end

return M
