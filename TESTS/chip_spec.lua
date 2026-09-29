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
    H.eq(c.text, "modern", "default text is modern")
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

  -- --------------------------------- dock_left default + a nonzero col_offset

  do
    -- Regression, found live: a user trying col_offset to nudge the chip
    -- got a box with its right/top/bottom border intact but no left edge
    -- at all -- exactly dock_left's own blank-left-border array, now
    -- visible away from the flush-left position that design assumes. Same
    -- fallback as the right-anchor case above, triggered by col_offset
    -- instead of anchor.
    setup({ chip = { enable = true, col_offset = 20 } }) -- anchor/shape left at their left/dock_left defaults
    local chip = load_module()
    local calls, restore = stub_recording_kit()
    chip.ensure_mounted()
    H.eq(
      calls[1][2].shape,
      "rounded_chip",
      "dock_left + a nonzero col_offset falls back to the symmetric shape"
    )
    restore()
  end

  do
    -- col_offset = 0 (the default -- "no offset") must NOT trigger the
    -- fallback; only an actual nonzero displacement does.
    setup({ chip = { enable = true, col_offset = 0 } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()
    chip.ensure_mounted()
    H.eq(
      calls[1][2].shape,
      "dock_left",
      "col_offset = 0 keeps dock_left, it isn't a real displacement"
    )
    restore()
  end

  do
    -- Regression, found live: a fractional col_offset (0.5) looked like it
    -- "fixed" the missing-left-border look, reading as col_offset itself
    -- having a real sub-cell effect. It does not -- `:h nvim_open_win()`
    -- documents Neovim's builtin (non-multigrid) row/col as always
    -- rounding DOWN to the nearest integer, so `0 + 0.5` renders on the
    -- exact same column `0 + 0` already does. The apparent fix was
    -- effective_shape()'s own fallback firing on any nonzero raw value,
    -- including one that floors away to no actual displacement at all.
    -- floor(0.5) == 0, so this must NOT trigger the fallback.
    setup({ chip = { enable = true, col_offset = 0.5 } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()
    chip.ensure_mounted()
    H.eq(
      calls[1][2].shape,
      "dock_left",
      "col_offset = 0.5 floors to 0 -- no real displacement, no fallback"
    )
    restore()
  end

  do
    -- The other side of the same fix: a fractional offset that DOES floor
    -- away from 0 (1.5 -> 1) must still trigger the fallback -- this is a
    -- real, visible displacement, just not an integer one as typed.
    setup({ chip = { enable = true, col_offset = 1.5 } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()
    chip.ensure_mounted()
    H.eq(
      calls[1][2].shape,
      "rounded_chip",
      "col_offset = 1.5 floors to 1 -- a real displacement, fallback fires"
    )
    restore()
  end

  do
    -- Negative offsets floor toward negative infinity (Lua's math.floor,
    -- matching Neovim's own documented rounding direction) -- -0.5 floors
    -- to -1, not 0, so it IS a real displacement and must trigger the
    -- fallback too.
    setup({ chip = { enable = true, col_offset = -0.5 } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()
    chip.ensure_mounted()
    H.eq(
      calls[1][2].shape,
      "rounded_chip",
      "col_offset = -0.5 floors to -1 -- a real displacement, fallback fires"
    )
    restore()
  end

  -- ------------------------------- dock_left default + a non-numeric col_offset

  do
    -- Regression, found by adversarial review, HIGH severity, live-
    -- reproduced: `cfg.chip.col_offset` is an UNVALIDATED config leaf
    -- (config/init.lua's KNOWN.chip.col_offset = true accepts any type).
    -- Before this fix, math.floor(col_offset) threw on a non-number --
    -- uncaught anywhere in the call chain up through setup() itself,
    -- since effective_shape() is called unconditionally, inline, while
    -- ensure_mounted() builds the table for kit_mod.chip.mount(). That
    -- aborted setup() ENTIRELY (keymaps never attach, autoload/autosave/
    -- dirty-tracking autocmds never register) -- and because
    -- sessions.init's _setup_done flag is set BEFORE this point, a retry
    -- silently no-ops forever; the only recovery was a config fix plus a
    -- Neovim restart. A single typo (e.g. col_offset = true, plausible
    -- next to the boolean-shaped dock/track_mode options a few lines
    -- away) must never be able to take down the whole plugin.
    setup({ chip = { enable = true, col_offset = true } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()
    local ok, err = pcall(chip.ensure_mounted)
    H.ok(ok, "ensure_mounted() must not throw on a non-numeric col_offset: " .. tostring(err))
    H.eq(
      calls[1][2].shape,
      "dock_left",
      "a non-numeric col_offset is not a real displacement -- no crash, no fallback"
    )
    restore()
  end

  do
    -- Same finding, the NaN/Infinity half: both satisfy Lua's
    -- `type(v) == \"number\"`, so a bare type() check alone would not have
    -- caught them, and `math.floor()` of either is itself, never 0 --
    -- which would misreport an unbounded/undefined offset as "a real
    -- displacement" instead of erroring outright.
    setup({ chip = { enable = true, col_offset = 0 / 0 } }) -- NaN
    local chip = load_module()
    local calls, restore = stub_recording_kit()
    local ok, err = pcall(chip.ensure_mounted)
    H.ok(ok, "ensure_mounted() must not throw on col_offset = NaN: " .. tostring(err))
    H.eq(calls[1][2].shape, "dock_left", "col_offset = NaN is not a real displacement")
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
        row_offset = 1,
        col_offset = -2,
        text = "classic_text", -- pins text() to a deterministic delegate below; "modern"'s own live behaviour is chip_text_spec.lua's job
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
    H.eq(calls[1][2].row_offset, 1, "cfg.chip.row_offset is forwarded")
    H.eq(calls[1][2].col_offset, -2, "cfg.chip.col_offset is forwarded")
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

  -- ------------------------------------------------------------------ toggle

  do
    setup({ chip = { enable = true, timeout_ms = false } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()

    chip.toggle()
    H.eq(#calls, 0, "toggle before the first ensure_mounted does nothing")

    chip.ensure_mounted()
    H.eq(#calls, 1, "ensure_mounted mounts once")

    -- ensure_mounted already left the chip visible.
    chip.toggle()
    H.eq(#calls, 2, "toggle while visible hides it")
    H.eq(calls[2][1], "refresh")

    chip.toggle()
    H.eq(#calls, 3, "toggle while hidden shows it again")
    H.eq(calls[3][1], "refresh")
    H.eq(#calls, 3, "no pulse call is ever recorded for toggle -- it is a look-up, not a flash")

    restore()
  end

  -- ------------------------------------------- toggle cancels a pending auto-hide

  do
    -- Regression: a manual toggle-off must supersede the auto-hide timer
    -- `ensure_mounted()` already scheduled -- without bumping the hide
    -- generation, that stale timer would fire later and refresh again,
    -- redundant at best and, for a shorter timeout than the wait below,
    -- capable of toggling a later manual show back off out from under it.
    setup({ chip = { enable = true, timeout_ms = 20 } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()

    chip.ensure_mounted()
    H.eq(#calls, 1)

    chip.toggle() -- manual hide, before the scheduled auto-hide fires
    H.eq(#calls, 2)
    H.eq(calls[2][1], "refresh")

    vim.wait(80, function()
      return false
    end, 10)
    H.eq(#calls, 2, "the superseded auto-hide timer does not fire a stray refresh")

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
