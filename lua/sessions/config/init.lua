---@module 'sessions.config'
--- Holds and merges the active `Sessions.Config`, applied by `M.setup()`
--- on top of `sessions.config.DEFAULTS`.

require("sessions.@types")

---@class SessionsConfigModule
local M = {}

---@type Sessions.Config
local DEFAULTS = require("sessions.config.DEFAULTS")

---@type Sessions.Config
M.cfg = vim.deepcopy(DEFAULTS)

---@internal
---Default blacklisted path prefixes for the current OS. Lives here (not in
---config/DEFAULTS.lua) because it is an environment lookup, and DEFAULTS
---must stay side-effect-free at require time -- see that module's header.
---Windows' actual %TEMP% value is re-checked and appended below too, since
---it varies per machine/user; this just avoids a Unix-only default on a
---fresh Windows install before setup() runs.
---@return string[]
local function default_blacklist_paths()
  if vim.fn.has("win32") == 1 then
    -- Slash-normalized, so the pair is "<temp>/" and "<temp>\" and not the
    -- mixed "C:/Users/.../Temp\" the earlier form produced -- a prefix that
    -- matches nothing, since a buffer name never mixes the two that way.
    local nix = vim.fn.expand("$TEMP"):gsub("\\", "/"):gsub("/+$", "")
    local win = nix:gsub("/", "\\")
    return { nix .. "/", win .. "\\" }
  end
  return { "/tmp/", "/private/tmp/" }
end

---@internal
---@param t table
---@return boolean
local function is_list(t)
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil then
      return false
    end
  end
  return true
end

---Top-level keys `setup()` recognizes and, for the nested tables among them,
---their own sub-keys -- recursively, to whatever depth `Sessions.Config`
---itself nests (e.g. `marks.menu`'s own keys, `ui`/`pin_marker`, are checked
---too, not just `marks`'s and `marks.menu`'s presence). `"list"` marks a
---curated array (`vim.tbl_deep_extend` replaces a non-empty array wholesale
---rather than index-merging it, so a stray scalar here would otherwise
---silently become one array entry instead of the type error it actually
---is). `"open"` marks a table whose keys are not a closed set (`root_remap`
---is an arbitrary old-root -> new-root map). `true` accepts any value
---unchecked -- covers scalars and leaf fields polymorphic enough (e.g.
---keymap values: `string|string[]|false`) that checking them here would
---duplicate what each consumer already guards for itself.
---@type table<string, true|"list"|"open"|table<string, any>>
local KNOWN = {
  root = true,
  default_name = true,
  branch_aware = true,
  project_aware = true,
  project_markers = "list",
  sessionoptions = true,
  relative_paths = true,
  root_remap = "open",
  autoload = true,
  autosave = true,
  autosave_name = true,
  metadata = true,
  restore_buffer_order = true,
  hooks = {
    on_save = true,
    on_load = true,
  },
  blacklist = {
    buftypes = true,
    filetypes = true,
    paths = true,
  },
  keymaps = {
    save = true,
    load = true,
    save_ts = true,
    list = true,
    current = true,
    picker = true,
    toggle_track = true,
    save_tab = true,
    load_tab = true,
    save_layout = true,
    load_layout = true,
    marks_menu = true,
    marks_edit = true,
    marks_add = true,
    marks_add_front = true,
    marks_pin = true,
    marks_remove = true,
    marks_sync = true,
    marks_debug = true,
    -- Real subcommands, deliberately unmappable (see docs/BINDINGS.md, "Why
    -- `delete` and `rename` have no keymap"): they must stay recognized here
    -- so validate() does not strip them from `clean.keymaps` before
    -- bindings/keymaps' own UNMAPPABLE table gets a chance to explain why,
    -- which is the whole point of that table existing.
    delete = true,
    rename = true,
  },
  which_key = {
    enable = true,
  },
  marks = {
    enable = true,
    scope = true,
    defaults = true,
    import_harpoon = true,
    context_debounce_ms = true,
    menu = {
      ui = true,
      pin_marker = true,
      preview_keys = true,
    },
    preview = {
      max_kb = true,
      max_lines = true,
    },
    select_key = true,
    preview_key = true,
  },
}

---Full dotted paths whose known-table entry also accepts a bare `false`
---instead of a table -- `keymaps = false` is the documented "register none"
---shape (config/DEFAULTS.lua's own default). Keyed by the same dotted path
---`validate_value()` builds up, so a nested field could opt in too, not only
---a top-level one -- none currently needs it.
---@type table<string, true>
local ALLOW_FALSE = { keymaps = true }

---What the last `setup()` had to reject or flag, for `:checkhealth`. Reset
---on every call so issues from an earlier setup() never linger.
---@type string[]
local issues = {}

---@internal
---`key` with the nearest known one as a hint when there is a plausible one
---(edit distance <= 3).
---@param key any
---@param known table<string, any>
---@param prefix string
---@return string
local function describe_unknown(key, known, prefix)
  local levenshtein = require("lib.lua.strings.distance").levenshtein
  local name = tostring(key)
  local best, best_distance = nil, nil
  for candidate in pairs(known) do
    local d = levenshtein(name, candidate)
    if d <= 3 and (best_distance == nil or d < best_distance) then
      best, best_distance = candidate, d
    end
  end
  if best then
    return ("unknown option '%s%s' (did you mean '%s%s'?)"):format(prefix, name, prefix, best)
  end
  return ("unknown option '%s%s'"):format(prefix, name)
end

---@internal
---Validate one `value` against its `known` entry (a `KNOWN[key]`, or one
---reached by recursing into it), to whatever depth `known` itself nests --
---an unknown key is caught no matter how deep it sits (ERR-50), and a value
---whose shape does not fit is dropped so the built-in default takes effect
---for that whole path instead of crashing a module downstream (ERR-22).
---@param value any
---@param known true|"list"|"open"|table<string, any>
---@param path string  full dotted path to `value`, for messages and ALLOW_FALSE
---@param found_issues string[]
---@return any clean  nil means "drop this path -- the caller must not set it"
local function validate_value(value, known, path, found_issues)
  if known == true then
    return value
  elseif known == "list" then
    if type(value) ~= "table" or not is_list(value) then
      found_issues[#found_issues + 1] = ("option '%s' must be a list, got %s -- using the default"):format(
        path,
        type(value)
      )
      return nil
    end
    return value
  elseif known == "open" then
    if type(value) ~= "table" then
      found_issues[#found_issues + 1] = ("option '%s' must be a table, got %s -- using the default"):format(
        path,
        type(value)
      )
      return nil
    end
    return value
  end
  -- type(known) == "table": a closed set of sub-keys, checked recursively.
  if value == false and ALLOW_FALSE[path] then
    return false
  end
  if type(value) ~= "table" then
    local shape = ALLOW_FALSE[path] and "a table or false" or "a table"
    found_issues[#found_issues + 1] = ("option '%s' must be %s, got %s -- using the default"):format(
      path,
      shape,
      type(value)
    )
    return nil
  end
  local sub_clean = {}
  for sub_key, sub_value in pairs(value) do
    local sub_known = known[sub_key]
    if sub_known == nil then
      found_issues[#found_issues + 1] = describe_unknown(sub_key, known, path .. ".")
    else
      local cleaned = validate_value(sub_value, sub_known, path .. "." .. sub_key, found_issues)
      if cleaned ~= nil then
        sub_clean[sub_key] = cleaned
      end
    end
  end
  return sub_clean
end

---Validate `opts` against `KNOWN` before the merge (ERR-50): an unknown key
---is dropped with a did-you-mean hint instead of silently vanishing into
---the default forever, and a value whose shape does not fit its option is
---dropped so the built-in default takes effect instead of crashing a module
---downstream (ERR-22). Recurses to arbitrary depth (see `validate_value()`),
---not just into the top-level tables. Does not mutate `opts`.
---@internal
---@param opts table
---@return table clean  a copy of opts holding only recognized, well-typed entries
---@return string[] found_issues
local function validate(opts)
  local clean, found_issues = {}, {}
  for key, value in pairs(opts) do
    local known = KNOWN[key]
    if known == nil then
      found_issues[#found_issues + 1] = describe_unknown(key, KNOWN, "")
    else
      local cleaned = validate_value(value, known, key, found_issues)
      if cleaned ~= nil then
        clean[key] = cleaned
      end
    end
  end
  table.sort(found_issues)
  return clean, found_issues
end

---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  local clean, found_issues = validate(opts)
  issues = found_issues

  M.cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), clean)
  M.cfg.root = require("lib.nvim.cross.fs.expand_path")(M.cfg.root)

  -- config/DEFAULTS.lua's own blacklist.paths is empty on purpose (LUA-06:
  -- it must stay side-effect-free at require time) -- resolve the platform
  -- default here unless the caller explicitly set their own.
  local user_set_paths = clean.blacklist and clean.blacklist.paths ~= nil
  if not user_set_paths then
    M.cfg.blacklist.paths = default_blacklist_paths()
  end

  -- Inject Windows %TEMP% into the blacklist automatically.
  --
  -- Both spellings, and that is the whole point: on Windows $TEMP is the 8.3
  -- short form (`C:/Users/STEFAN~1/...`) for any profile name over eight
  -- characters, while a buffer opened through a resolved path -- which is what
  -- fs_realpath, an LSP or a picker hands you -- carries the long one. The
  -- blacklist is a plain prefix compare, so registering only the short form
  -- let every long-spelled temp buffer straight into the session file.
  local temp = vim.fn.expand("$TEMP")
  if temp and temp ~= "" and temp ~= "$TEMP" then
    local uv = vim.uv or vim.loop
    local spellings = { temp }
    local real = uv.fs_realpath(temp)
    if real and real ~= temp then
      spellings[#spellings + 1] = real
    end

    local candidates = {}
    for _, spelling in ipairs(spellings) do
      local win = spelling:gsub("/", "\\"):gsub("\\+$", "")
      local nix = spelling:gsub("\\", "/"):gsub("/+$", "")
      candidates[#candidates + 1] = win
      candidates[#candidates + 1] = win .. "\\"
      candidates[#candidates + 1] = nix
      candidates[#candidates + 1] = nix .. "/"
    end

    for _, candidate in ipairs(candidates) do
      local found = false
      for _, p in ipairs(M.cfg.blacklist.paths) do
        if p == candidate then
          found = true
          break
        end
      end
      if not found then
        M.cfg.blacklist.paths[#M.cfg.blacklist.paths + 1] = candidate
      end
    end
  end
end

---@return Sessions.Config
function M.get()
  return M.cfg
end

---What the last `setup()` had to reject or flag: unknown keys (with a
---did-you-mean hint) and options whose value did not fit their expected
---shape, one human-readable line each. Empty when everything was recognized
---and well-typed.
---@return string[]
function M.issues()
  return vim.list_extend({}, issues)
end

return M
