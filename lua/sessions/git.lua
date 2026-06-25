---@module 'sessions.git'
--- Git helpers for branch/project-aware session naming.
--- Prefers lib.nvim when available; falls back to direct vim.fn calls.

local M = {}

---@return string|nil
function M.current_branch()
  local ok, git = pcall(require, "lib.nvim.git")
  if ok then
    return git.current_branch()
  end
  if vim.system then
    local res = vim.system({ "git", "symbolic-ref", "--short", "HEAD" }, { text = true }):wait()
    if res.code == 0 and res.stdout then
      return vim.trim(res.stdout)
    end
    return nil
  end
  local out = vim.fn.system("git symbolic-ref --short HEAD 2>/dev/null")
  if vim.v.shell_error ~= 0 then return nil end
  out = vim.trim(out)
  return out ~= "" and out or nil
end

---@param markers string[]
---@return string|nil
function M.project_root(markers)
  local ok, find_upward = pcall(require, "lib.nvim.fs.find_upward_dir")
  if ok then
    return find_upward(markers, vim.fn.getcwd())
  end
  local found = vim.fs.find(markers, { path = vim.fn.getcwd(), upward = true })
  if found and found[1] then
    return vim.fs.dirname(found[1])
  end
  return nil
end

--- Sanitize a string for use as a filesystem-safe session name segment.
---@param s string
---@return string
function M.sanitize(s)
  return s:gsub("[/\\%s]", "-"):gsub("[^%w%-_]", "_")
end

--- Resolve auto session name from project root and/or branch.
---@param cfg Sessions.Config
---@return string
function M.resolve_name(cfg)
  local parts = {}

  if cfg.project_aware then
    local root = M.project_root(cfg.project_markers)
    if root then
      local basename = vim.fn.fnamemodify(root, ":t")
      if basename and basename ~= "" then
        parts[#parts + 1] = M.sanitize(basename)
      end
    end
  end

  if cfg.branch_aware then
    local branch = M.current_branch()
    if branch then
      parts[#parts + 1] = M.sanitize(branch)
    end
  end

  if #parts > 0 then
    return table.concat(parts, "_")
  end
  return cfg.default_name
end

return M
