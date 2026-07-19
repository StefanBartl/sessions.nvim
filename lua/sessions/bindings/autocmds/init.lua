---@module 'sessions.bindings.autocmds'

local M = {}
local api = vim.api
local fn = vim.fn

---@return nil
function M.enable()
  local aug = api.nvim_create_augroup("SessionsNvim", { clear = true })

  local cfg = require("sessions.config").cfg

  if cfg.autoload then
    api.nvim_create_autocmd("VimEnter", {
      group = aug,
      callback = function()
        -- Only autoload when Neovim starts without explicit file arguments.
        if fn.argc(-1) == 0 then
          local ok, path = require("sessions.core").load(nil)
          if ok then
            vim.notify("[sessions] autoloaded: " .. (path or ""), vim.log.levels.INFO)
          end
        end
      end,
      desc = "sessions.nvim: autoload contextual session on startup",
      once = true,
      nested = true,
    })
  end

  if cfg.autosave then
    api.nvim_create_autocmd("VimLeavePre", {
      group = aug,
      callback = function()
        -- Save to fixed autosave_name (default "last") if set, otherwise don't save
        local name = cfg.autosave_name
        if name then
          require("sessions.core").save(name)
        end
      end,
      desc = "sessions.nvim: autosave to fixed session name on exit",
    })
  end
end

return M
