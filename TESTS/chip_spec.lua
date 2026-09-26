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

  -- ------------------------------------------------- enabled, ui.kit present

  do
    setup({
      chip = {
        enable = true,
        anchor = "top-right",
        shape = "rect",
        color = "DiagnosticInfo",
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
    setup({ chip = { enable = true, pulse = false } })
    local chip = load_module()
    local calls, restore = stub_recording_kit()

    chip.ensure_mounted()
    chip.pulse()
    H.eq(#calls, 1, "pulse = false: only the mount call, no pulse")

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
