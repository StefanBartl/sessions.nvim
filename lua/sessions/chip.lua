---@module 'sessions.chip'
---@brief Wires sessions.statusline's component into a `ui.kit.chip` corner
---indicator -- opt-in via `cfg.chip.enable`, soft dependency on `ui.kit`:
---silently does nothing without it installed, same as `bindings.autocmds`'
---own `kit.confirm` fallback.
---@description
---Only one session-status indicator is ever shown at a time: while the chip
---is actually visible, `bindings.usercmds`/`bindings.autocmds` skip the plain
---save/load/autoload notify entirely instead of showing it alongside the
---chip -- the chip's own text plus its `pulse()` already say the same thing.
---Without the chip (off, or `ui.kit` missing), the notify is exactly what it
---always was.
---
---The chip is not permanently on screen: `ensure_mounted()` (at startup) and
---`pulse()` (on every save/load/autoload) reveal it and schedule it to
---auto-hide again after `cfg.chip.timeout_ms` -- a brief status flash rather
---than a standing corner indicator, unless `timeout_ms` is `false` (or <= 0),
---which keeps the old always-on behaviour. `M.refresh()` (wired into the
---dirty-tracking structural autocmds) only updates the text/asterisk of an
---already-visible chip; it never reveals a hidden one by itself.

require("sessions.@types")

---@class SessionsChip
local M = {}

local CHIP_ID = "sessions"

---@type boolean
local mounted = false

---@type boolean
local visible = false

---Bumped on every `schedule_hide()` call so a stale deferred hide (from an
---earlier show) can recognize it has been superseded and no-op instead of
---hiding a chip a later show/pulse just revealed again.
---@type integer
local hide_generation = 0

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

---@internal
---`"dock_left"` (the default shape) blanks its own left border/corners on
---the assumption the chip sits flush against the screen's *left* edge --
---exactly what `anchor = "bottom-left"`/`"top-left"` (the default) puts it
---at, but backwards for `"bottom-right"`/`"top-right"`: the blank edge would
---then face into the middle of the screen and the rounded one would touch
---nothing, a visibly broken-looking box rather than a stylistic quirk.
---There is no mirrored `"dock_right"` preset (Issue 4 -- and this default --
---were only ever about the left corner), so a right-side anchor falls back
---to the plain, symmetric `"rounded_chip"` instead of forwarding a shape
---that would render wrong there. Only steps in for the shape ACTUALLY
---backing the dock look -- an explicit non-"dock_left" `shape` (e.g. a user
---who wants `"chip"`/`"classic"` at a right anchor) passes through
---untouched.
---An invalid/unrecognized `anchor` (config validation accepts any string
---unchecked -- there is no enum check) is resolved the same way
---`ui.kit.chip.mount()` itself resolves one: falls back to `"bottom-left"`,
---not treated as "not a left anchor". Without this, a typo'd anchor made
---this fall back to `"rounded_chip"` even though the chip actually ends up
---anchored bottom-left -- where `"dock_left"` would have been correct.
---@type table<string, true>
local VALID_ANCHORS = {
  ["bottom-left"] = true,
  ["bottom-right"] = true,
  ["top-left"] = true,
  ["top-right"] = true,
}

---@param anchor string
---@param shape string
---@return string
local function effective_shape(anchor, shape)
  local resolved_anchor = VALID_ANCHORS[anchor] and anchor or "bottom-left"
  if
    shape == "dock_left"
    and resolved_anchor ~= "bottom-left"
    and resolved_anchor ~= "top-left"
  then
    return "rounded_chip"
  end
  return shape
end

---@internal
---(Re)schedule hiding the chip after `cfg.chip.timeout_ms` ms, cancelling
---any previously scheduled hide first (the generation check below). A
---non-positive or non-number `timeout_ms` (`false` is the documented way to
---ask for this) means "persistent": no timer is scheduled at all, so the
---chip stays up once shown -- the pre-timeout default behaviour.
local function schedule_hide()
  hide_generation = hide_generation + 1
  local my_generation = hide_generation
  local timeout = cfg().timeout_ms
  if type(timeout) ~= "number" or timeout <= 0 then
    return
  end
  vim.defer_fn(function()
    if hide_generation ~= my_generation or not mounted then
      return
    end
    visible = false
    local kit_mod = kit()
    if kit_mod then
      kit_mod.chip.refresh(CHIP_ID)
    end
  end, timeout)
end

---Mount the chip once, if `cfg.chip.enable` and `ui.kit` is installed. Safe
---to call more than once (e.g. from `setup()` and again from a lazy
---`VimEnter`) -- only the first call after a config change actually mounts.
---Also starts the initial show/auto-hide cycle (see the module doc comment).
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
  visible = true
  kit_mod.chip.mount({
    id = CHIP_ID,
    -- Not `sessions.statusline.component()` (that stays a single-line
    -- string for the plain statusline segment, which genuinely cannot go
    -- multi-line) -- `cfg.chip.text`'s own formatter, re-read fresh here
    -- like every other field on this call.
    text = function()
      return require("sessions.chip_text").render(cfg().text)
    end,
    visible = function()
      return visible
    end,
    anchor = c.anchor,
    shape = effective_shape(c.anchor, c.shape),
    color = c.color,
    dock = c.dock,
    track_mode = c.track_mode,
    row_offset = c.row_offset,
    col_offset = c.col_offset,
  })
  mounted = true
  schedule_hide()
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

---Reveal the chip (even if a previous `timeout_ms` already hid it) and
---restart its auto-hide countdown, then flash its colour once, unless
---`cfg.chip.pulse` is `false` -- that only turns off the colour flash, the
---reveal/restart still happens. Called on every save/load/autoload. A no-op
---while the chip is off, not installed, or not mounted -- there is nothing
---to show before the first `ensure_mounted`.
---@return nil
function M.pulse()
  if not mounted then
    return
  end
  local kit_mod = kit()
  if not kit_mod then
    return
  end
  if not visible then
    visible = true
    kit_mod.chip.refresh(CHIP_ID)
  end
  schedule_hide()

  local c = cfg()
  if c.pulse == false then
    return
  end
  kit_mod.chip.pulse(CHIP_ID, { color = c.pulse_color, duration_ms = c.pulse_duration_ms })
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
