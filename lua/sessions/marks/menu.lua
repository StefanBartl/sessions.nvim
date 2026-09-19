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
--- The picker forms (`snacks`, `telescope`, `fzf`) show the same list with
--- shortened labels and open an entry in the current window, a split, a
--- vsplit or a tab. `auto` takes the first one installed and falls back to
--- `edit`, which needs nothing.

---@class SessionsMarksMenu
local M = {}

local marks = require("sessions.marks")

---@type string[]
M.KINDS = { "auto", "edit", "snacks", "telescope", "fzf" }

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
local function open_with(cmd, path)
  vim.cmd(cmd .. " " .. vim.fn.fnameescape(path))
  local at = marks.index(path)
  local items = at and marks.list() or nil
  if items and items[at] then
    local last = vim.api.nvim_buf_line_count(0)
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
---Flag every line that is a default or pin.
---@param buf integer
local function mark_pins(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  local pinned = marks.pinned_set()
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

  mark_pins(buf)

  local group = vim.api.nvim_create_augroup("SessionsMarksMenu", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = buf,
    callback = function()
      mark_pins(buf)
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
