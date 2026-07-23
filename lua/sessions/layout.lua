---@module 'sessions.layout'
--- Window-layout snapshots: capture/restore the split structure only (row
--- vs. col arrangement + sizes), independent of full sessions and without
--- touching buffers/files. Applied on top of whatever is currently open.

local api = vim.api
local fn = vim.fn

local M = {}

---@param cfg Sessions.Config
---@return string
local function layouts_dir(cfg)
  return cfg.root .. "/layouts"
end

---@param cfg Sessions.Config
---@param name string
---@return string
local function layout_path(cfg, name)
  return layouts_dir(cfg) .. "/" .. name .. ".json"
end

--- Walk winlayout()'s tree, replacing each `{"leaf", winid}` with
--- `{"leaf", {width=.., height=..}}` — winids don't survive a restart, sizes do.
---@param node any[]
---@return any[]
local function capture(node)
  if node[1] == "leaf" then
    local winid = node[2]
    return { "leaf", { width = api.nvim_win_get_width(winid), height = api.nvim_win_get_height(winid) } }
  end
  local kind, children = node[1], node[2]
  local out = {}
  for i, child in ipairs(children) do out[i] = capture(child) end
  return { kind, out }
end

---Capture the current tab's window layout (not its buffers) as `name`.
---@param name string
---@return boolean ok
---@return string path_or_err
function M.save(name)
  if type(name) ~= "string" or name == "" then
    return false, "layout name required"
  end
  local cfg = require("sessions.config").cfg
  if fn.isdirectory(layouts_dir(cfg)) == 0 then
    fn.mkdir(layouts_dir(cfg), "p")
  end

  local tree = capture(vim.fn.winlayout())
  local ok, encoded = pcall(vim.json.encode, tree)
  if not ok then return false, "failed to encode layout" end

  local path = layout_path(cfg, name)
  local f = io.open(path, "w")
  if not f then return false, "failed to write: " .. path end
  f:write(encoded)
  f:close()
  return true, path
end

--- Split `winid`'s area into `count` sibling windows arranged as `kind`
--- ("row" = left-to-right via vsplit, "col" = top-to-bottom via split),
--- returning the resulting window ids in order.
---@param kind string
---@param winid integer
---@param count integer
---@return integer[]
local function split_children(kind, winid, count)
  api.nvim_set_current_win(winid)
  local wins = { winid }
  for i = 2, count do
    vim.cmd(kind == "row" and "rightbelow vsplit" or "rightbelow split")
    wins[i] = api.nvim_get_current_win()
  end
  return wins
end

--- Recursively reconstruct `node` starting from `winid`, collecting each
--- resulting leaf window + its saved size into `out` for sizing once the
--- whole tree exists (sizing mid-build gets clobbered by later splits).
---@param node any[]
---@param winid integer
---@param out { win: integer, size: table }[]
local function build(node, winid, out)
  if node[1] == "leaf" then
    out[#out + 1] = { win = winid, size = node[2] }
    return
  end
  local kind, children = node[1], node[2]
  local wins = split_children(kind, winid, #children)
  for i, child in ipairs(children) do
    build(child, wins[i], out)
  end
end

---Restore a saved layout into the current tab, splitting whatever buffer(s)
---are currently open rather than touching what files are loaded.
---@param name string
---@return boolean ok
---@return string path_or_err
function M.restore(name)
  local cfg = require("sessions.config").cfg
  local path = layout_path(cfg, name)
  local f = io.open(path, "r")
  if not f then return false, "no such layout: " .. path end
  local content = f:read("*a")
  f:close()

  local ok, tree = pcall(vim.json.decode, content)
  if not ok or type(tree) ~= "table" then
    return false, "corrupt layout file: " .. path
  end

  pcall(vim.cmd, "silent! only!")

  local out = {}
  build(tree, api.nvim_get_current_win(), out)

  for _, entry in ipairs(out) do
    if entry.size.width then pcall(api.nvim_win_set_width, entry.win, entry.size.width) end
  end
  for _, entry in ipairs(out) do
    if entry.size.height then pcall(api.nvim_win_set_height, entry.win, entry.size.height) end
  end

  return true, path
end

---@return string[]  Absolute paths to saved layout .json files
function M.list()
  local cfg = require("sessions.config").cfg
  if fn.isdirectory(layouts_dir(cfg)) == 0 then return {} end
  local files = fn.globpath(layouts_dir(cfg), "*.json", false, true)
  table.sort(files)
  return files
end

---@param name string
---@return boolean ok
---@return string|nil path_or_err
function M.delete(name)
  local cfg = require("sessions.config").cfg
  local path = layout_path(cfg, name)
  if fn.filereadable(path) == 0 then
    return false, "layout not found: " .. name
  end
  local ok = os.remove(path)
  if not ok then return false, "failed to delete: " .. path end
  return true, path
end

return M
