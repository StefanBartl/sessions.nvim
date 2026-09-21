---@module 'sessions.marks.menu'
--- The ways to look at the mark list and pick from it.
---
--- `edit` is the one that can change the list: a floating scratch buffer
--- with one path per line, the pinned ones flagged at end of line. Reorder
--- lines, delete them, paste new ones -- closing the window (or `:w`) hands
--- the lines back to `sessions.marks.set_paths`. Deleting a *pinned* line
--- asks first, because a pin is a thing you decided to keep: keep it in the
--- list after all, drop it from the list only (it returns on the next
--- `defaults sync`), or unpin it too.
---
--- `kit`, `snacks`, `telescope` and `fzf` show the same list with a
--- preview and open an entry in the current window, a split, a vsplit or a
--- tab. `kit` (ui.nvim's `ui.kit.shortlist` -- a promptless list+preview,
--- no fuzzy search: this list rarely holds more than a handful of entries,
--- so there is nothing to search through) needs no picker plugin and is
--- tried first; `auto` then falls through `snacks`/`telescope`/`fzf` (the
--- first one installed) and finally `edit`, which needs nothing at all.
--- Concept and label formatting inspired by ThePrimeagen's harpoon.nvim --
--- thanks!

---@class SessionsMarksMenu
local M = {}

local marks = require("sessions.marks")

---@type string[]
M.KINDS = { "auto", "edit", "kit", "snacks", "telescope", "fzf" }

local NS = vim.api.nvim_create_namespace("sessions_marks_menu")
local HL = "SessionsMarksPin"

---@internal
---@return table
local function notify()
  local ok, lib = pcall(require, "lib.nvim.notify")
  if ok then
    return lib.create("[sessions.marks]")
  end
  return {
    info = function(msg)
      vim.notify("[sessions.marks] " .. msg, vim.log.levels.INFO)
    end,
    warn = function(msg)
      vim.notify("[sessions.marks] " .. msg, vim.log.levels.WARN)
    end,
    error = function(msg)
      vim.notify("[sessions.marks] " .. msg, vim.log.levels.ERROR)
    end,
  }
end

---@internal
---@return Sessions.Marks.Config
local function mcfg()
  return require("sessions.config").get().marks
end

---@internal
---@param cmd string  edit|split|vsplit|tabedit
---@param path string
---@param pos? { row: integer, col: integer }  # put the cursor here (1-based row, 0-based col) instead of at the mark's remembered position; clamped to the file
local function open_with(cmd, path, pos)
  vim.cmd(cmd .. " " .. vim.fn.fnameescape(path))
  local last = vim.api.nvim_buf_line_count(0)
  if pos then
    pcall(
      vim.api.nvim_win_set_cursor,
      0,
      { math.min(math.max(pos.row, 1), last), math.max(pos.col, 0) }
    )
    return
  end
  local at = marks.index(path)
  local items = at and marks.list() or nil
  if items and items[at] then
    pcall(vim.api.nvim_win_set_cursor, 0, {
      math.min(math.max(items[at].row, 1), last),
      math.max(items[at].col, 0),
    })
  end
end

-- ---------------------------------------------------------------- edit menu

---@type { buf: integer|nil, win: integer|nil }
local STATE = { buf = nil, win = nil }

---@internal
local function ensure_highlight()
  if vim.fn.hlexists(HL) == 0 then
    vim.api.nvim_set_hl(0, HL, { link = "DiagnosticVirtualTextWarn", default = true })
  end
end

---@internal
---Flag every line that is a default or pin. `pinned` is passed in rather
---than recomputed here (PERF-93): this runs on every `TextChanged`/
---`TextChangedI` in the edit buffer, i.e. on every keystroke, and
---`marks.pinned_set()` re-reads pins.json and re-resolves every configured
---default (a realpath syscall each) -- work whose result cannot change
---while this transient buffer is open, so the caller computes it once.
---@param buf integer
---@param pinned table<string, boolean>
local function mark_pins(buf, pinned)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  if not next(pinned) then
    return
  end
  local normkey = require("lib.nvim.fs.normkey")
  -- ERR-22: `pin_marker` is validated by config/init.lua's `validate()` only
  -- as "some value" (true in KNOWN, a leaf polymorphic enough that checking
  -- its shape there would duplicate this guard) -- so a non-string here (a
  -- config typo like `pin_marker = {}`) must degrade to the default rather
  -- than reach the `..` below, which errors on anything but a string/number.
  local raw = mcfg().menu and mcfg().menu.pin_marker
  local icon = type(raw) == "string" and raw or "📌 pin"
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local path = vim.trim(line)
    if path ~= "" and pinned[normkey(path, { realpath = true })] then
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, i - 1, 0, {
        virt_text = { { "  " .. icon, HL } },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })
    end
  end
end

---@internal
---The pinned entries that `lines` no longer contain, each confirmed with
---the user. Returns the lines to persist -- a declined removal is put back.
---@param lines string[]
---@return string[]
local function confirm_pinned_removals(lines)
  local normkey = require("lib.nvim.fs.normkey")
  local pinned = marks.pinned_set()
  if not next(pinned) then
    return lines
  end
  local present = {}
  for _, line in ipairs(lines) do
    local p = vim.trim(line)
    if p ~= "" then
      present[normkey(p, { realpath = true })] = true
    end
  end
  for _, it in ipairs(marks.list()) do
    local k = normkey(it.path, { realpath = true })
    if pinned[k] and not present[k] then
      local choice = vim.fn.confirm(
        ("A pinned entry is about to leave the list:\n%s"):format(it.path),
        "&List only\n&Unpin too\n&Keep it",
        1
      )
      if choice == 2 then
        local ok, err = marks.unpin(it.path)
        if not ok then
          notify().warn(tostring(err) .. " -- removed from the list only")
        end
      elseif choice == 3 or choice == 0 then
        lines[#lines + 1] = it.path
        present[k] = true
      end
    end
  end
  return lines
end

---@internal
---Persist the buffer's lines as the new list.
---@param buf integer
local function apply(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local before = #lines
  lines = confirm_pinned_removals(lines)
  if #lines > before then
    -- confirm_pinned_removals() only ever appends a kept pinned path to
    -- the end of `lines` -- write those lines into the BUFFER too, or the
    -- buffer stays out of sync with the store (it still looks like the
    -- entry was removed) and the same "about to leave the list" prompt
    -- fires again on the very next apply(), e.g. a second `:w`, or
    -- leaving the window right after one.
    local kept = {}
    for i = before + 1, #lines do
      kept[#kept + 1] = lines[i]
    end
    vim.api.nvim_buf_set_lines(buf, before, before, false, kept)
  end
  local items = marks.set_paths(lines)
  vim.bo[buf].modified = false
  return items
end

---@internal
local function close()
  if STATE.win and vim.api.nvim_win_is_valid(STATE.win) then
    pcall(vim.api.nvim_win_close, STATE.win, true)
  end
  STATE.win = nil
end

---Is the edit menu open?
---@return boolean
function M.is_open()
  return STATE.win ~= nil and vim.api.nvim_win_is_valid(STATE.win)
end

---Open the editable list. Opening it while it is open closes it.
---@return integer|nil buf
function M.open_edit()
  if M.is_open() then
    close()
    return nil
  end
  ensure_highlight()

  local items = marks.list()
  local lines = {}
  for i, it in ipairs(items) do
    lines[i] = it.path
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "sessions-marks"
  vim.api.nvim_buf_set_name(buf, "sessions://marks/" .. marks.scope_key())
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  local width = math.max(60, math.min(vim.o.columns - 4, 100))
  local height = math.max(8, math.min(#lines + 2, math.floor(vim.o.lines * 0.6)))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    style = "minimal",
    border = "rounded",
    title = (" marks (%s) "):format(marks.scope_key()),
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
  })
  vim.wo[win].number = true
  vim.wo[win].cursorline = true
  STATE.buf, STATE.win = buf, win

  -- Computed once for the lifetime of this menu session, not per keystroke
  -- (PERF-93) -- pins/defaults cannot change from inside this buffer.
  local pinned = marks.pinned_set()
  mark_pins(buf, pinned)

  local group = vim.api.nvim_create_augroup("SessionsMarksMenu", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function()
      mark_pins(buf, pinned)
    end,
  })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = buf,
    callback = function()
      apply(buf)
      notify().info("marks saved")
    end,
  })
  -- Leaving the window is a close: harpoon's menu behaves the same, and a
  -- float that lingers behind the buffer it opened is a nuisance.
  vim.api.nvim_create_autocmd({ "BufLeave", "WinClosed" }, {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      apply(buf)
      vim.schedule(close)
    end,
  })

  local map = function(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("q", close, "sessions marks: close")
  map("<Esc>", close, "sessions marks: close")
  map("<CR>", function()
    local line = vim.trim(vim.api.nvim_get_current_line())
    apply(buf)
    close()
    if line ~= "" then
      open_with("edit", line)
    end
  end, "sessions marks: open entry")
  for _, spec in ipairs({ { "<C-v>", "vsplit" }, { "<C-x>", "split" }, { "<C-t>", "tabedit" } }) do
    map(spec[1], function()
      local line = vim.trim(vim.api.nvim_get_current_line())
      apply(buf)
      close()
      if line ~= "" then
        open_with(spec[2], line)
      end
    end, "sessions marks: open entry in " .. spec[2])
  end
  return buf
end

-- ---------------------------------------------------------------- pickers

---@internal
---@return { path: string, label: string, row: integer, col: integer }[]
local function entries()
  local out = {}
  for i, it in ipairs(marks.list()) do
    out[i] = { path = it.path, label = marks.label(it.path), row = it.row, col = it.col }
  end
  return out
end

---@internal
---A promptless list+preview built on ui.kit -- no external picker plugin
---needed, and no fuzzy-search prompt to type past either, which suits a
---list that rarely holds more than a handful of entries. Preview sits above
---the results (ui.kit's `shortlist` template), both full width, so a path
---label can show more than a picker's narrow results column would leave
---room for.
---@return boolean handled
local function open_kit()
  local ok, kit = pcall(require, "ui.kit")
  if not ok then
    return false
  end
  local path_shorten = require("lib.nvim.fs.path_shorten")
  local normkey = require("lib.nvim.fs.normkey")
  local preview = require("sessions.marks.preview")
  local pinned = marks.pinned_set()
  local items = entries()
  if #items == 0 then
    return false
  end

  local raw = mcfg().menu and mcfg().menu.pin_marker
  local pin_icon = type(raw) == "string" and raw or "📌 pin"

  -- `marks.menu.preview_keys` goes to the kit as it is. Validated only as far as
  -- its shape (`config/init.lua` accepts any value there): anything but a table
  -- or `false` is a config typo and degrades to the kit's own defaults.
  local preview_keys = mcfg().menu and mcfg().menu.preview_keys
  if preview_keys ~= false and type(preview_keys) ~= "table" then
    preview_keys = nil
  end

  local function pin_suffix(path)
    if not pinned[normkey(path, { realpath = true })] then
      return ""
    end
    return "  " .. pin_icon
  end

  local h = kit.shortlist({
    items = items,
    title = ("Marks (%s)"):format(marks.scope_key()),
    -- Blocks interactive edits, same spirit as the standalone
    -- `:Session marks preview` float -- `surface:set_lines()` (used below)
    -- still works, it saves/restores `modifiable` around its own write.
    -- `readonly` is deliberately left alone: unlike the standalone float
    -- (which sets it only once, after its one-time write), this pane is
    -- rewritten on every selection change, and `nvim_buf_set_lines` logs a
    -- W10 warning on a `readonly` buffer even while `modifiable` is
    -- temporarily true -- that would fire on every arrow-key move here.
    preview_bo = { modifiable = false },
    format_item = function(item, width)
      local suffix = pin_suffix(item.path)
      local budget = width - vim.fn.strdisplaywidth(suffix)
      return path_shorten(item.path, math.max(1, budget)) .. suffix
    end,
    render = function(item, surface)
      local lines, truncated = preview.read_lines(item.path)
      if not lines then
        surface:set_lines({ "cannot read " .. item.path })
        return
      end
      if truncated then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "--- preview truncated ---"
      end
      surface:set_lines(lines)
      local ft = vim.filetype.match({ filename = item.path }) or ""
      pcall(vim.api.nvim_set_option_value, "filetype", ft, { buf = surface.bufnr })
      local total = math.max(#lines, 1)
      local row = math.min(math.max(item.row or 1, 1), total)
      pcall(vim.api.nvim_win_set_cursor, surface.winid, { row, math.max(item.col or 0, 0) })
    end,
    on_submit = function(item)
      open_with("edit", item.path)
    end,
    -- <CR> inside the preview: open the file where the preview cursor is, so a
    -- line found by scrolling (or by `/`) is the line you land on.
    on_preview_submit = function(item, _idx, pos)
      open_with("edit", item.path, pos)
    end,
    preview_keys = preview_keys,
  })
  if not h then
    return false
  end

  local mo = { buffer = h.results.bufnr, nowait = true }
  for _, spec in ipairs({ { "<C-v>", "vsplit" }, { "<C-x>", "split" }, { "<C-t>", "tabedit" } }) do
    vim.keymap.set("n", spec[1], function()
      local item = h.current_item()
      h.close()
      if item then
        open_with(spec[2], item.path)
      end
    end, mo)
  end
  return true
end

---@internal
---@return boolean handled
local function open_snacks()
  local ok, snacks = pcall(require, "snacks")
  if not ok or type(snacks.picker) ~= "table" then
    return false
  end
  local items = {}
  for i, e in ipairs(entries()) do
    items[i] = {
      idx = i,
      file = e.path,
      pos = { e.row, e.col },
      text = e.label .. " " .. e.path,
      label = e.label,
    }
  end
  snacks.picker.pick({
    source = "sessions_marks",
    title = "Marks (" .. marks.scope_key() .. ")",
    items = items,
    format = function(item)
      return { { ("%2d  "):format(item.idx), "SnacksPickerIdx" }, { item.label, "Normal" } }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        open_with("edit", item.file)
      end
    end,
    actions = {
      marks_split = function(picker, item)
        picker:close()
        if item then
          open_with("split", item.file)
        end
      end,
      marks_vsplit = function(picker, item)
        picker:close()
        if item then
          open_with("vsplit", item.file)
        end
      end,
      marks_tab = function(picker, item)
        picker:close()
        if item then
          open_with("tabedit", item.file)
        end
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-x>"] = { "marks_split", mode = { "n", "i" } },
          ["<C-v>"] = { "marks_vsplit", mode = { "n", "i" } },
          ["<C-t>"] = { "marks_tab", mode = { "n", "i" } },
        },
      },
    },
  })
  return true
end

---@internal
---@return boolean handled
local function open_telescope()
  if not pcall(require, "telescope") then
    return false
  end
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = "Marks (" .. marks.scope_key() .. ")",
      finder = finders.new_table({
        results = entries(),
        entry_maker = function(e)
          return {
            value = e,
            display = e.label,
            ordinal = e.label .. " " .. e.path,
            path = e.path,
            lnum = e.row,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = conf.file_previewer({}),
      attach_mappings = function(pb, map)
        local function with(cmd)
          return function()
            local e = action_state.get_selected_entry()
            actions.close(pb)
            if e then
              open_with(cmd, e.path)
            end
          end
        end
        actions.select_default:replace(with("edit"))
        for _, mode in ipairs({ "i", "n" }) do
          map(mode, "<C-v>", with("vsplit"))
          map(mode, "<C-x>", with("split"))
          map(mode, "<C-t>", with("tabedit"))
        end
        return true
      end,
    })
    :find()
  return true
end

---@internal
---@return boolean handled
local function open_fzf()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    return false
  end
  local lines = {}
  for i, e in ipairs(entries()) do
    lines[i] = ("%s\0%s"):format(e.label, e.path)
  end
  local function act(cmd)
    return function(selected)
      local p = (selected[1] or ""):match("\0(.*)$")
      if p then
        open_with(cmd, p)
      end
    end
  end
  fzf.fzf_exec(lines, {
    prompt = "Marks> ",
    fzf_opts = { ["--with-nth"] = "1", ["--delimiter"] = "\\x00" },
    previewer = "builtin",
    actions = {
      ["default"] = act("edit"),
      ["ctrl-x"] = act("split"),
      ["ctrl-v"] = act("vsplit"),
      ["ctrl-t"] = act("tabedit"),
    },
  })
  return true
end

---Open the list in `kind`, or in the configured/first available UI.
---@param kind string|nil  one of `M.KINDS`
function M.open(kind)
  kind = kind or (mcfg().menu and mcfg().menu.ui) or "auto"
  if #marks.list() == 0 and kind ~= "edit" then
    notify().info("no marks yet -- `:Session marks add`, or `:Session marks menu edit`")
    return
  end
  if kind == "edit" then
    M.open_edit()
    return
  end
  if kind == "kit" or kind == "auto" then
    if open_kit() then
      return
    elseif kind == "kit" then
      notify().warn("ui.nvim not available -- opening the edit menu")
    end
  end
  if kind == "snacks" or kind == "auto" then
    if open_snacks() then
      return
    elseif kind == "snacks" then
      notify().warn("snacks.nvim not available -- opening the edit menu")
    end
  end
  if kind == "telescope" or kind == "auto" then
    if open_telescope() then
      return
    elseif kind == "telescope" then
      notify().warn("telescope.nvim not available -- opening the edit menu")
    end
  end
  if kind == "fzf" or kind == "auto" then
    if open_fzf() then
      return
    elseif kind == "fzf" then
      notify().warn("fzf-lua not available -- opening the edit menu")
    end
  end
  M.open_edit()
end

return M
