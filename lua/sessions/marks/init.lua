---@module 'sessions.marks'
--- An ordered list of files you keep coming back to, with a cursor position
--- per file and a small set of *pinned* entries that survive a reset.
---
--- This is what a harpoon list is, minus the plugin. Its store is a JSON
--- file under the session root, one per *scope*: `"global"` (the default)
--- is one list for every project -- the same entries wherever Neovim was
--- started, which is what a list of notes, cheatsheets and a config file
--- wants -- and `"project"` keys the list by project root (and branch,
--- when `branch_aware` is on), the way sessions themselves are keyed.
---
--- Three kinds of entry, and the words used for them throughout:
---
---   * a **mark** is any entry in the live list;
---   * a **default** is a path from `marks.defaults` in the config -- the
---     committed set, expanded from `$REPOS_DIR`/`$HOME`/`$NVIM_HOME`
---     segments so the same config works on every machine;
---   * a **pin** is a default added at runtime (`:Session marks pin`),
---     stored machine-locally, never in the config.
---
--- Defaults and pins together are what `defaults sync` tops the list up
--- with and what `defaults reset` rebuilds it from. They are seeded once,
--- the first time the store is created; after that the list is the user's,
--- and nothing re-adds an entry that was deleted on purpose.
---
--- Every mutation writes the store. A cursor position is remembered when a
--- marked buffer is left (`sessions.bindings.autocmds`), debounced so a
--- burst of window switches costs one write.

require("sessions.@types")

---@class SessionsMarks
local M = {}

local uv = vim.uv or vim.loop
local normkey = require("lib.nvim.fs.normkey")
local json = require("lib.nvim.fs.json")

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
---@return Sessions.Config
local function config()
  return require("sessions.config").get()
end

---@internal
---@return Sessions.Marks.Config
local function mcfg()
  return config().marks
end

-- ---------------------------------------------------------------- paths

---Canonical absolute form of a path: expanded, normalized, symlinks
---resolved when the file exists. What the store holds.
---@param p string
---@return string
function M.canon(p)
  local abs = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(p), ":p"))
  local real = uv.fs_realpath(abs)
  if type(real) == "string" and real ~= "" then
    return vim.fs.normalize(real)
  end
  return abs
end

---@internal
---Identity of a path for comparisons: case of a drive letter, slashes and
---symlinks all folded, via lib.nvim's `normkey`.
---@param p string
---@return string
local function key_of(p)
  return normkey(p, { realpath = true })
end

---@internal
---@param p string
---@return boolean
local function is_file(p)
  local st = uv.fs_stat(p)
  return st ~= nil and st.type == "file"
end

---@internal
---`$REPOS_DIR`, `$HOME` and `$NVIM_HOME` as the first segment of a default
---spec; anything else is taken literally.
---@param sym string
---@return string
local function expand_var(sym)
  if sym == "$REPOS_DIR" then
    return vim.env.REPOS_DIR or ""
  elseif sym == "$HOME" then
    return (uv.os_homedir and uv.os_homedir()) or vim.fn.expand("~")
  elseif sym == "$NVIM_HOME" then
    return vim.fn.stdpath("config")
  end
  return sym
end

---Resolve one `marks.defaults` entry -- a list of path segments, or one
---string -- to an absolute path. `""` when the leading variable is unset.
---@param spec string|string[]
---@return string
function M.resolve_spec(spec)
  if type(spec) == "string" then
    return M.canon(expand_var(spec))
  end
  if type(spec) ~= "table" or #spec == 0 then
    return ""
  end
  local head = expand_var(spec[1])
  if head == "" then
    return ""
  end
  local parts = { head }
  for i = 2, #spec do
    parts[#parts + 1] = spec[i]
  end
  return M.canon(vim.fs.joinpath(unpack(parts)))
end

-- ---------------------------------------------------------------- scope

---The key the live list is stored under: `"global"`, or the project (and
---branch) for `marks.scope = "project"`.
---@return string
function M.scope_key()
  local cfg = config()
  if mcfg().scope ~= "project" then
    return "global"
  end
  local root = require("lib.nvim.fs.project_key")()
  local name = vim.fn.fnamemodify(root, ":t")
  if name == "" then
    name = "root"
  end
  local key = name .. "-" .. vim.fn.sha256(root):sub(1, 8)
  if cfg.branch_aware then
    local branch = require("sessions.git").current_branch()
    if branch and branch ~= "" then
      key = key .. "-" .. require("sessions.git").sanitize(branch)
    end
  end
  return key
end

---@internal
---@return string
local function store_dir()
  return config().root .. "/marks"
end

---Where the live list of the current scope is stored.
---@return string
function M.store_path()
  return store_dir() .. "/" .. M.scope_key() .. ".json"
end

---Where the machine-local pins are stored (one file, all scopes).
---@return string
function M.pins_path()
  return store_dir() .. "/pins.json"
end

---@internal
---@return string
local function seed_marker_path()
  return store_dir() .. "/.seeded-" .. M.scope_key()
end

-- ---------------------------------------------------------------- store

---@class Sessions.Mark
---@field path string   canonical absolute path
---@field row integer   1-based, last known cursor line
---@field col integer   0-based, last known cursor column

---@internal
---@return Sessions.Mark[]
local function read_items()
  local data = json.read(M.store_path())
  if type(data) ~= "table" or type(data.items) ~= "table" then
    return {}
  end
  local out, seen = {}, {}
  for _, it in ipairs(data.items) do
    local path = type(it) == "table" and it.path or it
    if type(path) == "string" and path ~= "" then
      local k = key_of(path)
      if not seen[k] then
        seen[k] = true
        out[#out + 1] = {
          path = path,
          row = type(it) == "table" and tonumber(it.row) or 1,
          col = type(it) == "table" and tonumber(it.col) or 0,
        }
      end
    end
  end
  return out
end

---@internal
---@param items Sessions.Mark[]
---@return boolean ok
local function write_items(items)
  vim.fn.mkdir(store_dir(), "p")
  local ok, err = json.write(M.store_path(), { version = 1, scope = M.scope_key(), items = items })
  if not ok then
    notify().error("cannot write " .. M.store_path() .. ": " .. tostring(err))
  end
  return ok
end

---The live list of the current scope, in order.
---@return Sessions.Mark[]
function M.list()
  return read_items()
end

---@internal
---@param items Sessions.Mark[]
---@param path string
---@return integer|nil index
local function index_of(items, path)
  local k = key_of(path)
  for i, it in ipairs(items) do
    if key_of(it.path) == k then
      return i
    end
  end
  return nil
end

---Position of `path` in the live list, or nil.
---@param path string
---@return integer|nil
function M.index(path)
  return index_of(read_items(), M.canon(path))
end

-- ---------------------------------------------------------------- pins and defaults

---@internal
---@return string[]
local function read_pins()
  local data = json.read(M.pins_path())
  if type(data) ~= "table" then
    return {}
  end
  local out = {}
  for _, p in ipairs(data) do
    if type(p) == "string" and p ~= "" then
      out[#out + 1] = p
    end
  end
  return out
end

---@internal
---@param pins string[]
---@return boolean
local function write_pins(pins)
  vim.fn.mkdir(store_dir(), "p")
  local ok, err = json.write(M.pins_path(), pins)
  if not ok then
    notify().error("cannot write " .. M.pins_path() .. ": " .. tostring(err))
  end
  return ok
end

---Every default path -- the config's `marks.defaults` in order, then the
---machine-local pins -- absolute and deduplicated. Paths that do not exist
---are kept here (so `is_pinned` still knows them) and skipped by `sync`.
---@return string[]
function M.defaults()
  local out, seen = {}, {}
  local function push(p)
    if p == "" then
      return
    end
    local k = key_of(p)
    if not seen[k] then
      seen[k] = true
      out[#out + 1] = p
    end
  end
  for _, spec in ipairs(mcfg().defaults or {}) do
    push(M.resolve_spec(spec))
  end
  for _, p in ipairs(read_pins()) do
    push(M.canon(p))
  end
  return out
end

---Identity set of every default and pin.
---@return table<string, boolean>
function M.pinned_set()
  local set = {}
  for _, p in ipairs(M.defaults()) do
    set[key_of(p)] = true
  end
  return set
end

---Is `path` a default or a pin?
---@param path string
---@return boolean
function M.is_pinned(path)
  return M.pinned_set()[key_of(path)] == true
end

-- ---------------------------------------------------------------- mutations

---@internal
---A path argument: `nil`/`""` means the current buffer. Must exist.
---@param path string|nil
---@return string|nil abs
---@return string|nil err
local function resolve_arg(path)
  if type(path) ~= "string" or path == "" then
    path = vim.api.nvim_buf_get_name(0)
    if path == "" then
      return nil, "the current buffer has no file name"
    end
  end
  local abs = M.canon(path)
  if not is_file(abs) then
    return nil, "not an existing file: " .. abs
  end
  return abs, nil
end

---Add a file to the list. Already listed: a no-op, unless `front` moves
---it to slot 1. `permanent` also pins it.
---@param path string|nil   nil = current buffer
---@param opts { front?: boolean, permanent?: boolean }|nil
---@return boolean ok
---@return string|nil err
function M.add(path, opts)
  opts = opts or {}
  local abs, err = resolve_arg(path)
  if not abs then
    return false, err
  end
  if opts.permanent then
    local ok, perr = M.pin(abs, { front = opts.front, quiet = true })
    if not ok then
      return false, perr
    end
  end
  local items = read_items()
  local at = index_of(items, abs)
  local row, col = 1, 0
  if at then
    if not opts.front or at == 1 then
      return true, "already listed"
    end
    row, col = items[at].row, items[at].col
    table.remove(items, at)
  end
  local entry = { path = abs, row = row, col = col }
  if opts.front then
    table.insert(items, 1, entry)
  else
    items[#items + 1] = entry
  end
  return write_items(items), nil
end

---Remove a file from the live list. A default or pin comes back on the
---next `defaults sync`; `unpin` is what makes that stop.
---@param path string|nil
---@return boolean removed
---@return string|nil err
function M.remove(path)
  local abs
  if type(path) == "string" and path ~= "" then
    abs = M.canon(path)
  else
    abs = vim.api.nvim_buf_get_name(0)
    if abs == "" then
      return false, "the current buffer has no file name"
    end
    abs = M.canon(abs)
  end
  local items = read_items()
  local at = index_of(items, abs)
  if not at then
    return false, "not in the list: " .. abs
  end
  table.remove(items, at)
  return write_items(items), nil
end

---Pin a file: a machine-local default, added to the live list now.
---@param path string|nil
---@param opts { front?: boolean, quiet?: boolean }|nil
---@return boolean ok
---@return string|nil err
function M.pin(path, opts)
  opts = opts or {}
  local abs, err = resolve_arg(path)
  if not abs then
    return false, err
  end
  local pins = read_pins()
  local k = key_of(abs)
  local already = false
  for _, p in ipairs(pins) do
    if key_of(M.canon(p)) == k then
      already = true
      break
    end
  end
  if not already then
    pins[#pins + 1] = abs
    if not write_pins(pins) then
      return false, "cannot write pins"
    end
  end
  local items = read_items()
  local at = index_of(items, abs)
  if not at then
    local entry = { path = abs, row = 1, col = 0 }
    if opts.front then
      table.insert(items, 1, entry)
    else
      items[#items + 1] = entry
    end
    write_items(items)
  elseif opts.front and at ~= 1 then
    local entry = table.remove(items, at)
    table.insert(items, 1, entry)
    write_items(items)
  end
  return true, already and "already pinned" or nil
end

---Stop treating a file as a default. Only a runtime pin can be unpinned; a
---config default is reported as such. The live entry stays.
---@param path string|nil
---@return boolean ok
---@return string|nil err
function M.unpin(path)
  local abs
  if type(path) == "string" and path ~= "" then
    abs = M.canon(path)
  else
    abs = vim.api.nvim_buf_get_name(0)
    if abs == "" then
      return false, "the current buffer has no file name"
    end
    abs = M.canon(abs)
  end
  local k = key_of(abs)
  local pins, kept, removed = read_pins(), {}, false
  for _, p in ipairs(pins) do
    if key_of(M.canon(p)) == k then
      removed = true
    else
      kept[#kept + 1] = p
    end
  end
  if not removed then
    for _, spec in ipairs(mcfg().defaults or {}) do
      if key_of(M.resolve_spec(spec)) == k then
        return false, "a config default (marks.defaults), not a runtime pin: " .. abs
      end
    end
    return false, "not a pin: " .. abs
  end
  return write_pins(kept), nil
end

---Top up: append every default or pin that is missing from the live list,
---in defaults order. Existing entries are left where they are.
---@return integer added
function M.defaults_sync()
  local items = read_items()
  local have = {}
  for _, it in ipairs(items) do
    have[key_of(it.path)] = true
  end
  local added = 0
  for _, p in ipairs(M.defaults()) do
    local k = key_of(p)
    if not have[k] and is_file(p) then
      items[#items + 1] = { path = p, row = 1, col = 0 }
      have[k] = true
      added = added + 1
    end
  end
  if added > 0 then
    write_items(items)
  end
  return added
end

---Hard reset: the live list becomes exactly the defaults and pins, in that
---order. Cursor positions of entries that stay are kept.
---@return integer count
function M.defaults_reset()
  local old = read_items()
  local items = {}
  for _, p in ipairs(M.defaults()) do
    if is_file(p) then
      local at = index_of(old, p)
      items[#items + 1] = { path = p, row = at and old[at].row or 1, col = at and old[at].col or 0 }
    end
  end
  write_items(items)
  return #items
end

---Replace the live list with `paths`, in that order -- what the editable
---menu hands back. Unknown paths are added, missing ones dropped, cursor
---positions of the survivors kept. Duplicates and blanks are ignored.
---@param paths string[]
---@return Sessions.Mark[] items
function M.set_paths(paths)
  local old = read_items()
  local items, seen = {}, {}
  for _, raw in ipairs(paths) do
    local p = vim.trim(raw)
    if p ~= "" then
      local abs = M.canon(p)
      local k = key_of(abs)
      if not seen[k] then
        seen[k] = true
        local at = index_of(old, abs)
        items[#items + 1] = {
          path = at and old[at].path or abs,
          row = at and old[at].row or 1,
          col = at and old[at].col or 0,
        }
      end
    end
  end
  write_items(items)
  return items
end

---Remember where the cursor was in a marked file. A no-op for a file that
---is not in the list, so it is safe to call from a `BufLeave` on anything.
---@param path string
---@param row integer
---@param col integer
---@return boolean changed
function M.update_context(path, row, col)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local items = read_items()
  local at = index_of(items, M.canon(path))
  if not at then
    return false
  end
  if items[at].row == row and items[at].col == col then
    return false
  end
  items[at].row, items[at].col = row, col
  return write_items(items)
end

-- ---------------------------------------------------------------- navigation

---Open entry `n` in the current window, cursor at its remembered position.
---@param n integer
---@return boolean ok
---@return string|nil err
function M.select(n)
  local items = read_items()
  local it = items[n]
  if not it then
    return false, ("no mark at %d (%d listed)"):format(n, #items)
  end
  if not is_file(it.path) then
    return false, "file is gone: " .. it.path
  end
  vim.cmd("edit " .. vim.fn.fnameescape(it.path))
  local last = vim.api.nvim_buf_line_count(0)
  pcall(
    vim.api.nvim_win_set_cursor,
    0,
    { math.min(math.max(it.row, 1), last), math.max(it.col, 0) }
  )
  return true, nil
end

-- ---------------------------------------------------------------- seeding and import

---@internal
---Claim the first run for this scope: creates the marker with `O_EXCL`, so
---of two Neovims starting together exactly one seeds.
---@return boolean first
local function claim_first_run()
  vim.fn.mkdir(store_dir(), "p")
  local fd, _, errname = uv.fs_open(seed_marker_path(), "wx", 420)
  if fd then
    uv.fs_close(fd)
    return true
  end
  return errname ~= "EEXIST"
end

---Harpoon v2's data files, newest first. Each is a JSON object keyed by
---harpoon's `settings.key()` value, whose `__harpoon_files` is a list of
---JSON-encoded items.
---@param data_dir string|nil  defaults to `stdpath("data")/harpoon`
---@return string[] paths
function M.harpoon_data_files(data_dir)
  data_dir = data_dir or (vim.fn.stdpath("data") .. "/harpoon")
  local files = {}
  local h = uv.fs_scandir(data_dir)
  if not h then
    return files
  end
  while true do
    local name, typ = uv.fs_scandir_next(h)
    if not name then
      break
    end
    if typ == "file" and name:sub(-5) == ".json" then
      local p = data_dir .. "/" .. name
      local st = uv.fs_stat(p)
      files[#files + 1] = { path = p, mtime = st and st.mtime.sec or 0 }
    end
  end
  table.sort(files, function(a, b)
    return a.mtime > b.mtime
  end)
  local out = {}
  for i, f in ipairs(files) do
    out[i] = f.path
  end
  return out
end

---Read one harpoon bucket out of a data file: the entries under `bucket`
---(compared as normalized paths), decoded. `nil` when the file holds no
---such bucket.
---@param file string
---@param bucket string
---@return { path: string, row: integer, col: integer }[]|nil
function M.read_harpoon_bucket(file, bucket)
  local data = json.read(file)
  if type(data) ~= "table" then
    return nil
  end
  local want = normkey(bucket)
  for key, value in pairs(data) do
    if type(key) == "string" and normkey(key) == want then
      local raw = type(value) == "table" and value.__harpoon_files or nil
      if type(raw) ~= "table" then
        return {}
      end
      local out = {}
      for _, encoded in ipairs(raw) do
        local ok, item = pcall(vim.json.decode, encoded)
        if ok and type(item) == "table" and type(item.value) == "string" then
          local ctx = type(item.context) == "table" and item.context or {}
          out[#out + 1] = {
            path = item.value,
            row = tonumber(ctx.row) or 1,
            col = tonumber(ctx.col) or 0,
          }
        end
      end
      return out
    end
  end
  return nil
end

---Import a harpoon list into the current scope's live list: harpoon's
---entries in harpoon's order, then whatever was already listed here that
---harpoon did not have. Existing files only.
---@param opts { bucket?: string, data_dir?: string }|nil  bucket defaults to `stdpath("config")`, the key a single-global-list harpoon setup uses
---@return integer imported
---@return string|nil err
function M.import_harpoon(opts)
  opts = opts or {}
  local bucket = opts.bucket or vim.fn.stdpath("config")
  local found
  for _, file in ipairs(M.harpoon_data_files(opts.data_dir)) do
    found = M.read_harpoon_bucket(file, bucket)
    if found then
      break
    end
  end
  if not found then
    return 0, "no harpoon bucket for " .. bucket
  end
  local items, seen = {}, {}
  for _, h in ipairs(found) do
    local abs = M.canon(h.path)
    local k = key_of(abs)
    if not seen[k] and is_file(abs) then
      seen[k] = true
      items[#items + 1] = { path = abs, row = h.row, col = h.col }
    end
  end
  local imported = #items
  for _, it in ipairs(read_items()) do
    local k = key_of(it.path)
    if not seen[k] then
      seen[k] = true
      items[#items + 1] = it
    end
  end
  write_items(items)
  return imported, nil
end

---Seed the store the first time it exists for this scope: from harpoon's
---list when `marks.import_harpoon` is on and one is found, else from the
---defaults. Every later call is a no-op.
---@param opts { data_dir?: string, bucket?: string }|nil  passed to `import_harpoon`
---@return string|nil what  "harpoon", "defaults", or nil when nothing happened
function M.seed_once(opts)
  if not claim_first_run() then
    return nil
  end
  if mcfg().import_harpoon ~= false then
    local n = M.import_harpoon(opts)
    if n > 0 then
      M.defaults_sync()
      return "harpoon"
    end
  end
  M.defaults_sync()
  return "defaults"
end

-- ---------------------------------------------------------------- display

---A short label for a path: `<root>/…/<parent>/<file>`.
---@param path string
---@return string
function M.label(path)
  return require("lib.nvim.fs.path_shorten")(path, nil, { style = "label" })
end

---The list as lines for a debug dump.
---@return string[]
function M.debug_lines()
  local items = read_items()
  local pinned = M.pinned_set()
  local lines = {
    ("scope: %s"):format(M.scope_key()),
    ("store: %s"):format(M.store_path()),
    ("items: %d"):format(#items),
  }
  for i, it in ipairs(items) do
    lines[#lines + 1] = ("%3d  %s%s  (%d:%d)"):format(
      i,
      pinned[key_of(it.path)] and "📌 " or "   ",
      M.label(it.path),
      it.row,
      it.col
    )
  end
  return lines
end

return M
