---@module 'sessions.util.notify'
---@brief The single notifier construction for sessions.nvim.
---@description
--- `lib.nvim.notify` is a soft dependency (see docs/installation.md): used
--- when available, a plain `vim.notify` fallback otherwise. Every caller
--- across this plugin (bindings/{autocmds,keymaps,usercmds}, marks/{init,menu,
--- preview}, picker.lua) used to duplicate that exact "create, or fall back"
--- logic in its own local closure -- seven near-identical copies, most of
--- them without `popup = true`/`source = "sessions"` even though the one
--- carrying both (bindings/autocmds) shows why: it is the difference between
--- a bare `vim.notify` sitting at the bottom of the screen indefinitely and a
--- self-dismissing, level-coloured toast that does not collide with the
--- `sessions.chip` status indicator living in the same corner.
---
--- This module is the one place that logic lives now. `create`/`create_titled`
--- deliberately do NOT cache by prefix: each caller already resolves once at
--- its own module-load time (or, for bindings/keymaps and the `notify()`
--- helpers in marks/*, once per call -- see each file's own comment), which
--- is also what lets a test stub `lib.nvim.notify` and reload just the one
--- consumer module under test.

local M = {}

---Builds a notifier for `prefix` (e.g. "[sessions]", "[sessions.marks]").
---Delivers via `lib.nvim.notify.popup` (toast + history, tagged
---`source = "sessions"` so `:Lib notify history sessions` covers every
---caller) when lib.nvim is installed, plain `vim.notify` otherwise.
---@param prefix string
---@return table notifier info/warn/error(msg, opts?)
function M.create(prefix)
  local ok, lib = pcall(require, "lib.nvim.notify")
  if ok then
    return lib.create(prefix, { popup = true, source = "sessions" })
  end
  return {
    info = function(msg, opts)
      vim.notify(prefix .. " " .. msg, vim.log.levels.INFO, opts)
    end,
    warn = function(msg, opts)
      vim.notify(prefix .. " " .. msg, vim.log.levels.WARN, opts)
    end,
    error = function(msg, opts)
      vim.notify(prefix .. " " .. msg, vim.log.levels.ERROR, opts)
    end,
  }
end

---Same as `create`, but every call additionally carries `cfg.notify_title`'s
---`{ title = "Sessions" }` (default on) -- picked up by a rich `vim.notify`
---backend (ui.nvim's `ui.notify`, nvim-notify, noice, snacks) that renders a
---title/colour from it, silently ignored by the plain fallback. Used where a
---caller wants that title (bindings/autocmds, bindings/usercmds).
---@param prefix string
---@return table notifier info/warn/error(msg)
function M.create_titled(prefix)
  local base = M.create(prefix)
  local cfg = require("sessions.config").cfg
  local title_opts = (cfg.notify_title ~= false) and { title = "Sessions" } or nil
  return {
    info = function(msg)
      base.info(msg, title_opts)
    end,
    warn = function(msg)
      base.warn(msg, title_opts)
    end,
    error = function(msg)
      base.error(msg, title_opts)
    end,
  }
end

return M
