---@module 'sessions.autocmds'

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
        require("sessions.core").save(nil)
      end,
      desc = "sessions.nvim: autosave contextual session on exit",
    })
  end
end

return M
