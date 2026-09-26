---@module 'sessions.chip'
---@brief Wires sessions.statusline's component into a persistent
---`ui.kit.chip` corner indicator -- opt-in via `cfg.chip.enable`, soft
---dependency on `ui.kit`: silently does nothing without it installed, same
---as `bindings.autocmds`' own `kit.confirm` fallback.
---@description
---Only one session-status indicator is ever shown at a time: while the chip
---is actually mounted (`is_active()`), `bindings.usercmds`/`bindings.autocmds`
---skip the plain save/load/autoload notify entirely instead of showing it
---alongside the chip -- the chip's own persistent text plus its `pulse()`
---already say the same thing. Without the chip (off, or `ui.kit` missing),
---the notify is exactly what it always was.

require("sessions.@types")

---@class SessionsChip
local M = {}

local CHIP_ID = "sessions"

---@type boolean
local mounted = false

---@internal
---@return table|nil kit  the `ui.kit` module, when both it and its `chip` submodule are present
local function kit()
  local ok, mod = pcall(require, "ui.kit")
  if ok and mod.chip then
    return mod
  end
  return nil
end

---@internal
---@return Sessions.Chip.Config
local function cfg()
  local c = require("sessions.config").cfg.chip
  ---@cast c Sessions.Chip.Config
  return c
end

---Mount the chip once, if `cfg.chip.enable` and `ui.kit` is installed. Safe
---to call more than once (e.g. from `setup()` and again from a lazy
---`VimEnter`) -- only the first call after a config change actually mounts.
---@return nil
function M.ensure_mounted()
  if mounted or not cfg().enable then
    return
  end
  local kit_mod = kit()
  if not kit_mod then
    return
  end
  local c = cfg()
  kit_mod.chip.mount({
    id = CHIP_ID,
    text = function()
      return require("sessions.statusline").component()
    end,
    anchor = c.anchor,
    shape = c.shape,
    color = c.color,
  })
  mounted = true
end

---Re-read the session state into the chip (its `text` provider is
---`sessions.statusline.component`, so this just tells `ui.kit.chip` to call
---it again). A no-op while the chip is off, not installed, or not mounted.
---@return nil
function M.refresh()
  if not mounted then
    return
  end
  local kit_mod = kit()
  if kit_mod then
    kit_mod.chip.refresh(CHIP_ID)
  end
end

---Flash the chip's colour once (save/load/autoload), unless `cfg.chip.pulse`
---is `false`. A no-op while the chip is off, not installed, or not mounted
----- there is nothing to flash before the first `ensure_mounted`/`refresh`.
---@return nil
function M.pulse()
  if not mounted then
    return
  end
  local c = cfg()
  if c.pulse == false then
    return
  end
  local kit_mod = kit()
  if kit_mod then
    kit_mod.chip.pulse(CHIP_ID, { color = c.pulse_color, duration_ms = c.pulse_duration_ms })
  end
end

---Whether the chip is actually mounted (`cfg.chip.enable` was true and
---`ui.kit` was present the first time `ensure_mounted()` ran). Callers use
---this to skip a one-shot notify that would otherwise say the same thing the
---chip already shows persistently -- see the module doc comment.
---@return boolean
function M.is_active()
  return mounted
end

return M
