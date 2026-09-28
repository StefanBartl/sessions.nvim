---@module 'sessions.chip_text'
---@brief Configurable, icon-capable text for the `ui.kit.chip` corner
---indicator -- separate from `sessions.statusline.component()`, which stays
---exactly as it is: a single-line string for the plain statusline segment,
---which genuinely cannot go multi-line. `sessions.chip.ensure_mounted()`
---wires this module's `render()` as the chip's own `text` provider instead.
---@description
---Folder/branch come from a *live* lookup (`sessions.git.project_root()`/
---`current_branch()`), never from parsing the resolved session *name* back
---apart -- a name like `nvim-usercmds-env-vars-3560c9_claude-cursor-jump-
---save-1f9524` has underscores on both sides of the real project/branch
---split, so there is no reliable way to un-concatenate it. Querying live
---also means the chip stays accurate even for a session loaded under an
---unrelated custom name.

require("sessions.@types")

---@class SessionsChipText
local M = {}

-- Byte-escaped, not literal glyphs: a private-use-area character pasted
-- straight into source has silently stripped to nothing before, going
-- through some editors/tools -- see `ui.statusline.utils.primitives`'s own
-- `ICON_GIT_ADDED`/etc. for the exact same convention and the bug
-- ("counter with no icon") it exists to avoid.
---@type Sessions.Chip.TextIcons
local DEFAULT_ICONS = {
  -- neo-tree's own built-in `folder_closed` default (U+E5FF) -- this user's
  -- actual neo-tree spec currently overrides it to an empty string (looks
  -- like the exact same silent-glyph-loss accident, unrelated to this
  -- feature and not this module's place to fix), so this is neo-tree's own
  -- intended default, what a folder icon *would* show there.
  folder = "\xEE\x97\xBF",
  -- Matches `ui.statusline.utils.primitives.ICON_GIT_BRANCH` exactly --
  -- the same glyph this user's own statusline already shows for a branch.
  branch = "\xEE\xA9\xA8",
}

---@internal
---@param cfg Sessions.Chip.TextConfig|Sessions.Chip.TextPreset|nil
---@return Sessions.Chip.TextConfig
local function resolve_cfg(cfg)
  if type(cfg) == "string" then
    cfg = { preset = cfg }
  end
  cfg = cfg or {}
  return {
    preset = cfg.preset or "modern",
    icons = vim.tbl_extend("force", DEFAULT_ICONS, cfg.icons or {}),
    -- No default filled in here for "modern" -- its own built-in shape
    -- (one line per part that actually resolved, see M.render() below) is
    -- NOT the same as this fixed template rendered with empty parts
    -- substituted. `template` stays nil unless the caller set one.
    template = cfg.template,
  }
end

---@internal
---Substitute `{folder}`/`{branch}`/`{icon.folder}`/`{icon.branch}`
---placeholders in `template` from `values`. An unrecognized placeholder
---(a typo) renders as empty rather than erroring -- consistent with how a
---missing folder/branch part already renders in the built-in "modern"
---shape, and safer than raising out of a `text` provider `ui.kit.chip`
---itself already pcalls, but which this module's own tests should still
---be able to assert against directly.
---@param template string
---@param values table<string, string>
---@return string
local function render_template(template, values)
  return (template:gsub("{([%w%.]+)}", function(key)
    return values[key] or ""
  end))
end

---@internal
---Live folder/branch, honouring `branch_aware`/`project_aware` exactly the
---way `sessions.git.resolve_name()` already does for the session name
---itself -- an aware flag being off means "do not resolve this part",
---not "resolve it but do not use it for naming".
---@return string|nil folder
---@return string|nil branch
local function live_parts()
  local cfg = require("sessions.config").cfg
  local git = require("sessions.git")

  local folder = nil
  if cfg.project_aware then
    local root = git.project_root(cfg.project_markers)
    if root and root ~= "" then
      local basename = vim.fn.fnamemodify(root, ":t")
      folder = (basename and basename ~= "") and basename or nil
    end
  end

  local branch = nil
  if cfg.branch_aware then
    local b = git.current_branch()
    branch = (b and b ~= "") and b or nil
  end

  return folder, branch
end

---Build the chip's text for `cfg` (`sessions.config.cfg.chip.text`, a
---preset name or the full table -- see `Sessions.Chip.TextConfig`).
---@param cfg? Sessions.Chip.TextConfig|Sessions.Chip.TextPreset
---@return string
function M.render(cfg)
  local resolved = resolve_cfg(cfg)

  if resolved.preset == "classic_text" then
    return require("sessions.statusline").component()
  end

  local folder, branch = live_parts()

  if resolved.template then
    -- An explicit template is the caller's own layout, honoured literally
    -- even with an empty part substituted in -- but still not for NEITHER
    -- part resolving at all, which is "nothing to show" regardless of
    -- template.
    if not folder and not branch then
      return require("sessions.statusline").component()
    end
    return render_template(resolved.template, {
      folder = folder or "",
      branch = branch or "",
      ["icon.folder"] = resolved.icons.folder,
      ["icon.branch"] = resolved.icons.branch,
    })
  end

  -- "modern"'s own built-in shape: one line per part that actually
  -- resolved -- never an icon rendered next to nothing, which is what a
  -- fixed two-line template would do for whichever half of
  -- branch_aware/project_aware is off (or fails to resolve on its own,
  -- e.g. a detached HEAD has no branch even with branch_aware on).
  local lines = {}
  if folder then
    lines[#lines + 1] = resolved.icons.folder .. " " .. folder
  end
  if branch then
    lines[#lines + 1] = resolved.icons.branch .. " " .. branch
  end
  if #lines == 0 then
    return require("sessions.statusline").component()
  end
  return table.concat(lines, "\n")
end

return M
