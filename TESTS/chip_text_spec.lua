-- TESTS/chip_text_spec.lua — sessions.chip_text: the chip's own configurable,
-- icon-capable text, separate from sessions.statusline.component() (which
-- stays single-line, for the plain statusline segment).
--
-- sessions.git is stubbed throughout: this file is about chip_text's own
-- composition (which preset renders what, the fallback, the template
-- substitution), not sessions.git's live lookup logic (git_spec.lua's job).

return function(H)
  local config = require("sessions.config")

  local function setup(extra)
    config.setup(vim.tbl_deep_extend("force", { chip = { enable = false } }, extra or {}))
  end

  -- Fresh load: nothing in this module is stateful, but matching the rest
  -- of this suite's own convention keeps it consistent.
  local function chip_text()
    return H.fresh("sessions.chip_text")
  end

  -- --------------------------------------------------------- classic_text

  do
    setup({ branch_aware = true, project_aware = true })
    local restore = H.stub("sessions.statusline", {
      component = function()
        return "nvim_main *"
      end,
    })
    H.eq(
      chip_text().render("classic_text"),
      "nvim_main *",
      "classic_text delegates straight to statusline.component(), verbatim"
    )
    H.eq(
      chip_text().render({ preset = "classic_text" }),
      "nvim_main *",
      "...the same whether given as a bare string or { preset = ... }"
    )
    restore()
  end

  -- ---------------------------------------------------------------- modern

  do
    setup({ branch_aware = true, project_aware = true })
    local restore = H.stub("sessions.git", {
      project_root = function()
        return "/home/me/my-project"
      end,
      current_branch = function()
        return "feature/login"
      end,
    })
    H.eq(
      chip_text().render("modern"),
      "\xEE\x97\xBF my-project\n\xEE\xA9\xA8 feature/login",
      "modern: one icon-prefixed line per part, folder then branch"
    )
    restore()
  end

  do
    -- Only the folder resolves (branch_aware off) -- one line, not two with
    -- an icon next to nothing.
    setup({ branch_aware = false, project_aware = true })
    local restore = H.stub("sessions.git", {
      project_root = function()
        return "/home/me/my-project"
      end,
      current_branch = function()
        error("must not be called: branch_aware is off")
      end,
    })
    H.eq(
      chip_text().render("modern"),
      "\xEE\x97\xBF my-project",
      "modern with only project_aware on: just the folder line"
    )
    restore()
  end

  do
    -- Only the branch resolves (project_aware off) -- symmetric case.
    setup({ branch_aware = true, project_aware = false })
    local restore = H.stub("sessions.git", {
      project_root = function()
        error("must not be called: project_aware is off")
      end,
      current_branch = function()
        return "feature/login"
      end,
    })
    H.eq(
      chip_text().render("modern"),
      "\xEE\xA9\xA8 feature/login",
      "modern with only branch_aware on: just the branch line"
    )
    restore()
  end

  do
    -- Neither *_aware is on -- nothing to show, falls all the way back.
    setup({ branch_aware = false, project_aware = false })
    local restore_git = H.stub("sessions.git", {
      project_root = function()
        error("must not be called: project_aware is off")
      end,
      current_branch = function()
        error("must not be called: branch_aware is off")
      end,
    })
    local restore_stl = H.stub("sessions.statusline", {
      component = function()
        return "raw-name"
      end,
    })
    H.eq(
      chip_text().render("modern"),
      "raw-name",
      "modern falls back to classic_text's output when neither part resolves"
    )
    restore_stl()
    restore_git()
  end

  do
    -- Both *_aware are on, but the live lookup itself comes up with
    -- nothing (e.g. a detached HEAD, or project_root() finding no marker)
    -- -- same fallback as the *_aware-off case above.
    setup({ branch_aware = true, project_aware = true })
    local restore_git = H.stub("sessions.git", {
      project_root = function()
        return nil
      end,
      current_branch = function()
        return nil
      end,
    })
    local restore_stl = H.stub("sessions.statusline", {
      component = function()
        return "raw-name"
      end,
    })
    H.eq(
      chip_text().render("modern"),
      "raw-name",
      "an empty live lookup falls back the same as *_aware being off"
    )
    restore_stl()
    restore_git()
  end

  -- ------------------------------------------------------------- template

  do
    setup({ branch_aware = true, project_aware = true })
    local restore = H.stub("sessions.git", {
      project_root = function()
        return "/x/my-project"
      end,
      current_branch = function()
        return "main"
      end,
    })
    H.eq(
      chip_text().render({
        template = "[{folder}] ({icon.folder}) -- [{branch}] ({icon.branch})",
      }),
      "[my-project] (\xEE\x97\xBF) -- [main] (\xEE\xA9\xA8)",
      "a custom template round-trips every placeholder, folder/branch/both icons"
    )
    restore()
  end

  do
    -- An explicit template renders even with one part empty (unlike
    -- "modern"'s own built-in shape, which omits that line entirely) --
    -- the caller asked for this exact layout.
    setup({ branch_aware = false, project_aware = true })
    local restore = H.stub("sessions.git", {
      project_root = function()
        return "/x/my-project"
      end,
      current_branch = function()
        error("must not be called: branch_aware is off")
      end,
    })
    H.eq(
      chip_text().render({ template = "{folder}|{branch}" }),
      "my-project|",
      "an explicit template substitutes an empty string for the missing part"
    )
    restore()
  end

  do
    -- ...but still falls back when NEITHER part resolves at all -- an
    -- explicit template with nothing to fill in is not a reason to show it
    -- with every placeholder blank.
    setup({ branch_aware = false, project_aware = false })
    local restore_stl = H.stub("sessions.statusline", {
      component = function()
        return "raw-name"
      end,
    })
    H.eq(
      chip_text().render({ template = "{folder}|{branch}" }),
      "raw-name",
      "a template still falls back to classic_text when neither part resolves"
    )
    restore_stl()
  end

  -- ----------------------------------------------------------------- icons

  do
    setup({ branch_aware = true, project_aware = true })
    local restore = H.stub("sessions.git", {
      project_root = function()
        return "/x/my-project"
      end,
      current_branch = function()
        return "main"
      end,
    })
    H.eq(
      chip_text().render({ preset = "modern", icons = { folder = ">" } }),
      "> my-project\n\xEE\xA9\xA8 main",
      "overriding one icon leaves the other at its own default"
    )
    restore()
  end

  config.setup({})
end
