---@module 'sessions.picker'
--- :SessionLoad — session picker with live preview (buffer list + timestamp
--- + branch, from metadata) and multi-select delete. Backed by
--- Snacks.picker (preferred) or telescope.nvim, whichever is available —
--- neither is a hard dependency; :SessionLoad just errors out with a clear
--- message if neither is installed.

local M = {}

---@class Sessions.PickerItem
---@field name string
---@field path string
---@field current boolean
---@field meta Sessions.Meta|nil

---@return Sessions.PickerItem[]
local function collect()
  local core = require("sessions.core")
  local current = core.current()
  local items = {}
  for _, path in ipairs(core.list()) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    items[#items + 1] = {
      name = name,
      path = path,
      current = (name == current),
      meta = core.metadata(name),
    }
  end
  return items
end

---@param item Sessions.PickerItem
---@return string[]
local function preview_lines(item)
  local lines = { "Session: " .. item.name, "" }
  local meta = item.meta
  if meta then
    if meta.saved_at then lines[#lines + 1] = "Saved:  " .. meta.saved_at end
    if meta.branch then lines[#lines + 1] = "Branch: " .. meta.branch end
    if meta.cwd then lines[#lines + 1] = "Cwd:    " .. meta.cwd end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Buffers:"
    for _, b in ipairs(meta.buffers or {}) do
      lines[#lines + 1] = "  " .. b
    end
  else
    lines[#lines + 1] = "(no metadata recorded — enable `metadata = true` for buffer list/timestamp/branch)"
  end
  return lines
end

---@param names string[]
local function do_delete(names)
  local core = require("sessions.core")
  local ok_n, notify = pcall(require, "lib.nvim.notify")
  local n = ok_n and notify.create("[sessions]") or {
    info = function(msg) vim.notify("[sessions] " .. msg, vim.log.levels.INFO) end,
  }
  for _, name in ipairs(names) do
    core.delete(name)
  end
  n.info("deleted: " .. table.concat(names, ", "))
end

---@return boolean handled
local function pick_snacks()
  local ok, Snacks = pcall(require, "snacks")
  if not ok or not Snacks.picker then return false end

  local items = {}
  for i, it in ipairs(collect()) do
    items[i] = {
      idx = i,
      text = it.name,
      name = it.name,
      current = it.current,
      preview = { text = table.concat(preview_lines(it), "\n") },
    }
  end

  Snacks.picker.pick({
    title = "Sessions",
    items = items,
    format = function(item)
      local mark = item.current and "* " or "  "
      return { { mark .. item.name, item.current and "SnacksPickerSpecial" or "Normal" } }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        require("sessions.core").load(item.name)
      end
    end,
    actions = {
      sessions_delete = function(picker)
        local sel = picker:selected({ fallback = true })
        if #sel == 0 then return end
        local names = {}
        for _, it in ipairs(sel) do names[#names + 1] = it.name end
        do_delete(names)

        local kept = {}
        for _, it in ipairs(picker.opts.items) do
          if not vim.tbl_contains(names, it.name) then kept[#kept + 1] = it end
        end
        picker.opts.items = kept
        picker:refresh()
      end,
    },
    win = {
      input = { keys = { ["<C-d>"] = { "sessions_delete", mode = { "n", "i" } } } },
      list = { keys = { ["<C-d>"] = "sessions_delete" } },
    },
  })
  return true
end

---@return boolean handled
local function pick_telescope()
  local ok = pcall(require, "telescope")
  if not ok then return false end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  local function open()
    pickers.new({}, {
      prompt_title = "Sessions",
      finder = finders.new_table({
        results = collect(),
        entry_maker = function(it)
          return {
            value = it,
            display = (it.current and "* " or "  ") .. it.name,
            ordinal = it.name,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = previewers.new_buffer_previewer({
        define_preview = function(self, entry)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, preview_lines(entry.value))
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            require("sessions.core").load(entry.value.name)
          end
        end)

        -- Multi-select toggling (<Tab>/<S-Tab>) uses Telescope's own
        -- defaults; only the delete action is custom here.
        local function delete_selected()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local sel = picker:get_multi_selection()
          if #sel == 0 then
            local cur = action_state.get_selected_entry()
            if cur then sel = { cur } end
          end
          if #sel == 0 then return end

          local names = {}
          for _, entry in ipairs(sel) do names[#names + 1] = entry.value.name end
          actions.close(prompt_bufnr)
          do_delete(names)
          open()
        end

        map("i", "<C-d>", delete_selected)
        map("n", "<C-d>", delete_selected)

        return true
      end,
    }):find()
  end

  open()
  return true
end

---Open the session picker (Snacks.picker preferred, falls back to Telescope).
---<CR> loads the selected session; <C-d> deletes the (multi-)selection.
function M.pick()
  if #require("sessions.core").list() == 0 then
    vim.notify("[sessions] no sessions saved yet", vim.log.levels.INFO)
    return
  end
  if pick_snacks() then return end
  if pick_telescope() then return end
  vim.notify(
    "[sessions] :SessionLoad requires snacks.nvim (with picker) or telescope.nvim",
    vim.log.levels.ERROR
  )
end

return M
