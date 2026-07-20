---@module 'sessions.bindings.autocmds'

local M = {}
local api = vim.api
local fn = vim.fn

-- lib.nvim is a soft dependency here, matching the fallback convention used
-- in bindings/keymaps and bindings/usercmds (see health.lua).
local autocmd_ok, autocmd = pcall(require, "lib.nvim.autocmd")

local notify_ok, notify_lib = pcall(require, "lib.nvim.notify")
local n = notify_ok and notify_lib.create("[sessions]") or {
  info = function(msg) vim.notify("[sessions] " .. msg, vim.log.levels.INFO) end,
}

---@param event string
---@param callback fun(args: table)
---@param opts table
local function create_autocmd(event, callback, opts)
  if autocmd_ok then
    autocmd.create(event, callback, opts)
  else
    opts.callback = callback
    api.nvim_create_autocmd(event, opts)
  end
end

---@return nil
function M.enable()
  local cfg = require("sessions.config").cfg

  local aug = autocmd_ok and autocmd.group("SessionsNvim", true)
    or api.nvim_create_augroup("SessionsNvim", { clear = true })

  if cfg.autoload then
    create_autocmd("VimEnter", function()
      -- Only autoload when Neovim starts without explicit file arguments.
      if fn.argc(-1) == 0 then
        local ok, path = require("sessions.core").load(nil)
        if ok then
          n.info("autoloaded: " .. (path or ""))
        end
      end
    end, {
      group = aug,
      desc = "sessions.nvim: autoload contextual session on startup",
      once = true,
      nested = true,
    })
  end

  if cfg.autosave then
    create_autocmd("VimLeavePre", function()
      -- Save to fixed autosave_name (default "last") if set, otherwise don't save
      local name = cfg.autosave_name
      if name then
        require("sessions.core").save(name)
      end
    end, {
      group = aug,
      desc = "sessions.nvim: autosave to fixed session name on exit",
    })
  end
end

return M
