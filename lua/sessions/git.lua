---@module 'sessions.git'
--- Git helpers for branch/project-aware session naming.
--- Prefers lib.nvim when available; falls back to direct vim.fn calls.

local M = {}

---@return string|nil
function M.current_branch()
  local ok, git = pcall(require, "lib.nvim.git")
  if ok then
    local branch = git.current_branch()
    -- Guard against lib.nvim returning error-like strings
    return (branch and branch ~= "" and not branch:lower():find("error")) and branch or nil
  end
  if vim.system then
    local res = vim.system({ "git", "symbolic-ref", "--short", "HEAD" }, { text = true }):wait()
    if res.code == 0 and res.stdout then
      return vim.trim(res.stdout)
    end
    return nil
  end
  -- Fallback: vim.fn.system (check error code, reject error-like output)
  local out = vim.fn.system("git symbolic-ref --short HEAD")
  if vim.v.shell_error ~= 0 then return nil end
  out = vim.trim(out)
  -- Reject if it looks like an error message
  if out == "" or out:lower():find("error") or out:lower():find("not a") then
    return nil
  end
  return out
end

---@param markers string[]
---@return string|nil
function M.project_root(markers)
  local ok, find_upward = pcall(require, "lib.nvim.fs.find_upward_dir")
  if ok then
    local root = find_upward(markers, vim.fn.getcwd())
    -- Guard against lib.nvim returning error-like strings
    if root and root ~= "" and not root:lower():find("error") then
      return root
    end
    return nil
  end
  -- Fallback: vim.fs.find (Neovim built-in)
  local found = vim.fs.find(markers, { path = vim.fn.getcwd(), upward = true })
  if found and found[1] then
    local dir = vim.fs.dirname(found[1])
    if dir and dir ~= "" then
      return dir
    end
  end
  return nil
end

--- Sanitize a string for use as a filesystem-safe session name segment.
--- Filters out ANSI color codes, error patterns, and non-filename-safe chars.
---@param s string
---@return string
function M.sanitize(s)
  if not s or s == "" then return "" end
  -- Remove ANSI escape sequences (colors, formatting)
  s = s:gsub("\27%[[0-9;]*m", "")
  -- Reject strings that look like error messages
  if s:lower():find("error") or s:lower():find("could not") or
     s:lower():find("not found") or s:lower():find("permission") then
    return ""
  end
  -- Replace unsafe chars: slashes, backslashes, whitespace
  s = s:gsub("[/\\%s]", "-")
  -- Replace other unsafe chars with underscore
  s = s:gsub("[^%w%-_]", "_")
  -- Clean up multiple consecutive dashes/underscores
  s = s:gsub("[-_]+", "-")
  return s
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
        local sanitized = M.sanitize(basename)
        -- Only add if sanitize() didn't filter it out
        if sanitized ~= "" then
          parts[#parts + 1] = sanitized
        end
      end
    end
  end

  if cfg.branch_aware then
    local branch = M.current_branch()
    if branch then
      local sanitized = M.sanitize(branch)
      -- Only add if sanitize() didn't filter it out
      if sanitized ~= "" then
        parts[#parts + 1] = sanitized
      end
    end
  end

  if #parts > 0 then
    return table.concat(parts, "_")
  end
  return cfg.default_name
end

return M
