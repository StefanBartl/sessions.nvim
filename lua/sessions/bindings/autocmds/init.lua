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

--- Minimal floating y/n prompt for `autoload = "ask"`. Not a vim.ui.select
--- (that renders as a command-line menu, not a floating window) — the
--- roadmap asks for an actual floating prompt.
---@param question string
---@param callback fun(yes: boolean)
local function float_confirm(question, callback)
  local text = " " .. question .. " "
  local hint = " [y]es / [n]o "
  local width = math.max(#text, #hint)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, { text, hint })
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = 2,
    row = math.floor((vim.o.lines - 2) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
  })

  local done = false
  local function finish(yes)
    if done then return end
    done = true
    if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
    if api.nvim_buf_is_valid(buf) then api.nvim_buf_delete(buf, { force = true }) end
    callback(yes)
  end

  local kopts = { buffer = buf, nowait = true, silent = true }
  for _, key in ipairs({ "y", "Y", "<CR>" }) do
    vim.keymap.set("n", key, function() finish(true) end, kopts)
  end
  for _, key in ipairs({ "n", "N", "<Esc>", "q" }) do
    vim.keymap.set("n", key, function() finish(false) end, kopts)
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
      if fn.argc(-1) ~= 0 then return end

      local core = require("sessions.core")

      local function do_autoload()
        local ok, path = core.load(nil)
        if ok then
          n.info("autoloaded: " .. (path or ""))
        end
      end

      if cfg.autoload == "ask" then
        local si, exists = core.peek()
        if not exists then return end
        float_confirm(("Restore session '%s'?"):format(si.name), function(yes)
          if yes then do_autoload() end
        end)
      else
        do_autoload()
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

    -- Structural layout changes are what the next autosave would actually
    -- capture, so mark the session dirty for statusline consumers
    -- (see sessions.statusline) rather than tracking buffer `modified`.
    for _, event in ipairs({ "BufAdd", "BufDelete", "WinNew", "WinClosed", "TabNewEntered", "TabClosed" }) do
      create_autocmd(event, function()
        require("sessions.core").mark_dirty()
      end, {
        group = aug,
        desc = "sessions.nvim: mark session dirty for statusline",
      })
    end
  end
end

return M
