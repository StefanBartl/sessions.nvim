-- TESTS/chip_spec.lua — sessions.chip: the persistent ui.kit.chip wrapper
-- around sessions.statusline.component(). `is_active()` (whether the chip
-- actually mounted) is what bindings/usercmds and bindings/autocmds use to
-- skip the save/load/autoload notify -- see usercmds_spec.lua/
-- autocmds_spec.lua for that side of the contract; this file covers the
-- module's own mount/refresh/pulse/is_active behaviour in isolation.
--
-- `ui.kit` is genuinely not installed here (same situation as
-- autocmds_spec.lua's own note), so every path is exercised via `H.stub`:
-- absent entirely, present but without a `chip` submodule (an older
-- version), and present with one that records what it was called with.

return function(H)
  local config = require("sessions.config")

  ---@param extra table|nil
  local function setup(extra)
    config.setup(vim.tbl_deep_extend("force", { chip = { enable = false } }, extra or {}))
  end

  ---Load the module fresh: its `mounted` flag is a module-level local, so a
  ---cached instance would remember an earlier block's mount forever.
  ---@return table
  local function load_module()
    return H.fresh("sessions.chip")
  end

  ---@return table calls, fun() restore
  local function stub_recording_kit()
    local calls = {}
    local restore = H.stub("ui.kit", {
      chip = {
        mount = function(opts)
          calls[#calls + 1] = { "mount", opts }
        end,
        refresh = function(id)
          calls[#calls + 1] = { "refresh", id }
        end,
        pulse = function(id, opts)
          calls[#calls + 1] = { "pulse", id, opts }
        end,
      },
    })
    return calls, restore
  end

  -- ---------------------------------------------------- chip.enable = false

  do
    setup()
    local chip = load_module()
    local calls, restore = stub_recording_kit()

    chip.ensure_mounted()
    H.eq(#calls, 0, "enable = false: mount is never called")
    H.falsy(chip.is_active(), "and is_active() says so")
    chip.refresh()
    chip.pulse()
    H.eq(#calls, 0, "...nor are refresh/pulse")

    restore()
  end

  -- ------------------------------------------------- enabled, ui.kit absent

  do
    setup({ chip = { enable = true } })
    local chip = load_module()
    local restore = H.stub("ui.kit", false)

    H.ok(pcall(chip.ensure_mounted), "no ui.kit: ensure_mounted does not error")
    H.falsy(chip.is_active(), "and it never became active")
    H.ok(pcall(chip.refresh), "...nor does refresh")
    H.ok(pcall(chip.pulse), "...nor does pulse")

    restore()
  end

  -- --------------------------------- enabled, ui.kit present without .chip

  do
    -- An installed ui.kit predating the chip submodule -- same soft-dependency
    -- shape as "not installed at all", not a crash.
    setup({ chip = { enable = true } })
    local chip = load_module()
    local restore = H.stub("ui.kit", {})

    H.ok(pcall(chip.ensure_mounted), "ui.kit without .chip: ensure_mounted does not error")

    restore()
  end

  -- ---------------------------------------------------------- config defaults

  do
    -- The chip is meant to be a brief startup/save/load flash, bottom-left,
    -- docked flush against the statusline -- not the old permanent
    -- top-right indicator, nor a box floating free above the statusline
    -- with a gap. Asserted directly against the resolved config rather than
    -- through the mount plumbing.
    config.setup({})
    local c = config.cfg.chip
    H.eq(c.anchor, "bottom-left", "default anchor is bottom-left")
    H.eq(c.shape, "dock_left", "default shape is dock_left")
    H.ok(c.dock, "default dock is true")
    H.falsy(c.track_mode, "default track_mode is false (opt-in)")
    H.eq(c.timeout_ms, 3000, "default timeout_ms is 3000 (3s)")
  end

  -- ----------------------------- dock_left default + a right-side anchor

  do
    -- Regression, found by adversarial review of the new "dock_left"
    -- default: it blanks its own left border/corners on the assumption the
    -- chip sits flush against the screen's LEFT edge -- exactly backwards
    -- for a right-side anchor (the blank edge would face into the screen,
    -- the rounded one would touch nothing). anchor and shape are validated
    -- independently (config/init.lua's KNOWN table), so nothing catches
    -- this combination before it reaches kit.chip.mount() -- ensure_mounted()
    -- itself has to correct for it.
    setup({ chip = { enable = true, anchor = "bottom-right" } }) -- shape left at its "dock_left" default
    local chip = load_module()
    local calls, restore = stub_recording_kit()

    chip.ensure_mounted()
    H.eq(
      calls[1][2].shape,
      "rounded_chip",
      "dock_left + a right-side anchor falls back to the symmetric shape"
    )

    restore()
  end

  do
    -- The same fallback must NOT kick in for the left anchors dock_left is
    -- actually meant for, nor for an explicit shape override that has
    -- nothing to do with the dock look.
    setup({ chip = { enable = true, anchor = "top-left" } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()
    chip.ensure_mounted()
    H.eq(
      calls[1][2].shape,
      "dock_left",
      "dock_left stays dock_left at a left anchor (top-left too)"
    )
    restore()
  end

  do
    -- Regression, found by a second round of adversarial review: an invalid
    -- anchor string (config validation accepts any string unchecked, so a
    -- typo reaches here) used to fall back to "rounded_chip" too eagerly --
    -- ui.kit.chip.mount() itself resolves an unrecognized anchor to
    -- "bottom-left", where "dock_left" is actually correct.
    setup({ chip = { enable = true, anchor = "typo-left" } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()
    chip.ensure_mounted()
    H.eq(
      calls[1][2].shape,
      "dock_left",
      "an invalid anchor resolves like kit.chip's own bottom-left fallback, not a forced rounded_chip"
    )
    restore()
  end

  do
    setup({ chip = { enable = true, anchor = "bottom-right", shape = "classic" } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()
    chip.ensure_mounted()
    H.eq(calls[1][2].shape, "classic", "an explicit non-dock_left shape passes through untouched")
    restore()
  end

  -- ------------------------------------------------- enabled, ui.kit present

  do
    setup({
      chip = {
        enable = true,
        anchor = "top-right",
        shape = "rect",
        color = "DiagnosticInfo",
        dock = false,
        track_mode = true,
        timeout_ms = false, -- persistent for this block: it tests call-forwarding, not the auto-hide timer
        pulse = true,
        pulse_color = "DiagnosticError",
        pulse_duration_ms = 42,
      },
    })
    local chip = load_module()
    local calls, restore = stub_recording_kit()

    chip.ensure_mounted()
    H.eq(#calls, 1, "ensure_mounted mounts once")
    H.ok(chip.is_active(), "is_active() reflects the successful mount")
    H.eq(calls[1][1], "mount")
    H.eq(calls[1][2].id, "sessions")
    H.eq(calls[1][2].anchor, "top-right", "cfg.chip.anchor is forwarded")
    H.eq(calls[1][2].shape, "rect", "cfg.chip.shape is forwarded")
    H.eq(calls[1][2].color, "DiagnosticInfo", "cfg.chip.color is forwarded")
    H.falsy(calls[1][2].dock, "cfg.chip.dock is forwarded")
    H.ok(calls[1][2].track_mode, "cfg.chip.track_mode is forwarded")
    H.eq(type(calls[1][2].text), "function", "text is a provider function, not a snapshot")

    local restore_statusline = H.stub("sessions.statusline", {
      component = function()
        return "STUBBED"
      end,
    })
    H.eq(calls[1][2].text(), "STUBBED", "text() delegates to sessions.statusline.component()")
    restore_statusline()

    chip.ensure_mounted()
    H.eq(#calls, 1, "a second ensure_mounted does not mount again")

    chip.refresh()
    H.eq(#calls, 2)
    H.eq(calls[2][1], "refresh")
    H.eq(calls[2][2], "sessions")

    chip.pulse()
    H.eq(#calls, 3)
    H.eq(calls[3][1], "pulse")
    H.eq(calls[3][2], "sessions")
    H.eq(calls[3][3].color, "DiagnosticError", "cfg.chip.pulse_color is forwarded")
    H.eq(calls[3][3].duration_ms, 42, "cfg.chip.pulse_duration_ms is forwarded")

    restore()
  end

  -- ------------------------------------------------------------ pulse = false

  do
    setup({ chip = { enable = true, pulse = false, timeout_ms = false } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()

    chip.ensure_mounted()
    chip.pulse()
    -- Already visible from ensure_mounted, so the reveal is a no-op too.
    H.eq(#calls, 1, "pulse = false: only the mount call, no pulse")

    restore()
  end

  -- --------------------------------------------- timeout_ms auto-hide + pulse reveal

  do
    -- A short real timeout so the test observes the actual auto-hide behind
    -- `vim.defer_fn`, then confirms `pulse()` revives a chip that already
    -- faded out and re-arms a fresh countdown.
    setup({ chip = { enable = true, timeout_ms = 20 } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()

    chip.ensure_mounted()
    H.eq(#calls, 1, "ensure_mounted mounts once")
    H.eq(calls[1][1], "mount")

    H.ok(
      vim.wait(500, function()
        return #calls >= 2
      end, 10),
      "the chip auto-hides (a second call) within timeout_ms"
    )
    H.eq(calls[2][1], "refresh", "auto-hide re-syncs through refresh, not a new mount")

    chip.pulse()
    H.eq(#calls, 4, "pulse on a hidden chip: one refresh to reveal it, one pulse to flash it")
    H.eq(calls[3][1], "refresh", "pulse reveals the faded-out chip first")
    H.eq(calls[4][1], "pulse")

    H.ok(
      vim.wait(500, function()
        return #calls >= 5
      end, 10),
      "pulse re-armed the countdown: the chip auto-hides again"
    )
    H.eq(calls[5][1], "refresh")

    restore()
  end

  -- ---------------------------------------------------------- refresh before mount

  do
    -- enable = true but ensure_mounted() was never called: refresh/pulse must
    -- stay no-ops rather than mounting implicitly on the side.
    setup({ chip = { enable = true } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()

    chip.refresh()
    chip.pulse()
    H.eq(#calls, 0, "refresh/pulse before the first ensure_mounted do nothing")

    restore()
  end

  package.loaded["sessions.chip"] = nil
  config.setup({})
end
