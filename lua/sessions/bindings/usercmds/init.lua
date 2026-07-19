---@module 'sessions.bindings.usercmds'

local M = {}

-- Resolve a notifier once per session; graceful fallback if lib.nvim absent.
local _n
local function n()
  if _n then return _n end
  local ok, lib = pcall(require, "lib.nvim.notify")
  if ok then
    _n = lib.create("[sessions]")
  else
    _n = {
      info  = function(msg) vim.notify("[sessions] " .. msg, vim.log.levels.INFO) end,
      warn  = function(msg) vim.notify("[sessions] " .. msg, vim.log.levels.WARN) end,
      error = function(msg) vim.notify("[sessions] " .. msg, vim.log.levels.ERROR) end,
    }
  end
  return _n
end

---@return string[]
local function complete_names()
  local list = require("sessions.core").list()
  local out = {}
  for i = 1, #list do
    out[i] = vim.fn.fnamemodify(list[i], ":t:r")
  end
  return out
end

---@return nil
function M.enable()
  local nc = vim.api.nvim_create_user_command

  nc("SessionSave", function(cmd)
    local arg = cmd.args ~= "" and cmd.args or nil
    local ok, res = require("sessions.core").save(arg)
    if ok then n().info("saved: " .. (res or "?"))
    else      n().error("save failed: " .. (res or "?")) end
  end, {
    nargs = "?",
    complete = function() return complete_names() end,
    desc = "Save session [name] (tab-complete to overwrite an existing one)",
  })

  nc("SessionSaveTimestamp", function()
    local stamp = os.date("sess-%Y%m%d-%H%M%S")
    local ok, res = require("sessions.core").save(stamp)
    if ok then n().info("saved: " .. (res or "?"))
    else      n().error("save failed: " .. (res or "?")) end
  end, { desc = "Save session with timestamp suffix" })

  nc("SessionLoad", function(cmd)
    local arg = cmd.args ~= "" and cmd.args or nil
    local ok, res, hidden = require("sessions.core").load(arg)
    if ok then
      n().info("loaded: " .. (res or "?"))
      if hidden and #hidden > 0 then
        n().info("hidden (unsaved): " .. table.concat(hidden, ", "))
      end
    else
      n().error("load failed: " .. (res or "?"))
    end
  end, {
    nargs = "?",
    complete = function() return complete_names() end,
    desc = "Load session [name]",
  })

  nc("SessionDelete", function(cmd)
    if cmd.args == "" then n().error("usage: SessionDelete <name>"); return end
    local ok, res = require("sessions.core").delete(cmd.args)
    if ok then n().info("deleted: " .. cmd.args)
    else      n().error("delete failed: " .. (res or "?")) end
  end, {
    nargs = 1,
    complete = function() return complete_names() end,
    desc = "Delete a session by name",
  })

  nc("SessionRename", function(cmd)
    local args = vim.split(cmd.args, "%s+", { trimempty = true })
    if #args ~= 2 then n().error("usage: SessionRename <old> <new>"); return end
    local ok, res = require("sessions.core").rename(args[1], args[2])
    if ok then n().info(("renamed '%s' → '%s'"):format(args[1], args[2]))
    else      n().error("rename failed: " .. (res or "?")) end
  end, {
    nargs = "+",
    complete = function() return complete_names() end,
    desc = "Rename a session: SessionRename <old> <new>",
  })

  nc("SessionList", function()
    local list = require("sessions.core").list()
    if #list == 0 then print("No sessions saved."); return end
    local current = require("sessions.core").current()
    for _, p in ipairs(list) do
      local name = vim.fn.fnamemodify(p, ":t:r")
      local meta = require("sessions.core").metadata(name)
      local star   = (name == current) and " *" or "  "
      local ts     = (meta and meta.saved_at) and ("  " .. meta.saved_at) or ""
      local branch = (meta and meta.branch)   and ("  [" .. meta.branch .. "]") or ""
      print(star .. name .. ts .. branch)
    end
  end, { desc = "List all saved sessions" })

  nc("SessionCurrent", function()
    local cur = require("sessions.core").current()
    print(cur and ("Current session: " .. cur) or "No session active.")
  end, { desc = "Print the active session name" })

  -- Toggle git skip-worktree on a session file so it can live in a config repo
  -- but be excluded from commits on machines where the paths don't exist.
  nc("SessionToggleTrack", function(cmd)
    local cfg  = require("sessions.config").cfg
    local name = cmd.args ~= "" and cmd.args
      or require("sessions.core").current()
      or cfg.default_name
    local file = cfg.root .. "/" .. name .. ".vim"

    if vim.fn.filereadable(file) == 0 then
      n().error("session file not found: " .. file)
      return
    end

    -- Find the git root that contains the session storage directory.
    local git_root
    if vim.system then
      local r = vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = cfg.root, text = true }):wait()
      if r.code == 0 then git_root = vim.trim(r.stdout or "") end
    end
    if not git_root or git_root == "" then
      local ok_argv, run_argv = pcall(require, "lib.nvim.cross.run_argv")
      if ok_argv then
        local ok_run, out = run_argv.run_blocking_captured({ "git", "-C", cfg.root, "rev-parse", "--show-toplevel" })
        git_root = ok_run and vim.trim(out) or ""
      else
        git_root = vim.trim(vim.fn.system(
          "git -C " .. vim.fn.shellescape(cfg.root) .. " rev-parse --show-toplevel 2>/dev/null"
        ))
      end
    end
    if git_root == "" then
      n().error("session root is not inside a git repo (required for SessionToggleTrack)")
      return
    end

    local function is_skipped(f)
      if vim.system then
        local r = vim.system({ "git", "ls-files", "-v", "--", f }, { cwd = git_root, text = true }):wait()
        return ((r.stdout or ""):match("^S")) ~= nil
      end
      local ok_argv, run_argv = pcall(require, "lib.nvim.cross.run_argv")
      if ok_argv then
        local _, out = run_argv.run_blocking_captured({ "git", "-C", git_root, "ls-files", "-v", "--", f })
        return (out or ""):match("^S") ~= nil
      end
      local out = vim.fn.system(
        "git -C " .. vim.fn.shellescape(git_root) .. " ls-files -v -- " .. vim.fn.shellescape(f)
      )
      return (out or ""):match("^S") ~= nil
    end

    local skipped = is_skipped(file)
    local toggle_args = skipped
      and { "git", "update-index", "--no-skip-worktree", "--", file }
      or  { "git", "update-index", "--skip-worktree",    "--", file }

    local code
    if vim.system then
      code = vim.system(toggle_args, { cwd = git_root, text = true }):wait().code
    else
      local ok_argv, run_argv = pcall(require, "lib.nvim.cross.run_argv")
      if ok_argv then
        local cwd_args = { "git", "-C", git_root }
        for _, a in ipairs(toggle_args) do cwd_args[#cwd_args + 1] = a end
        local ok_run = run_argv.run_blocking(cwd_args)
        code = ok_run and 0 or 1
      else
        vim.fn.system(table.concat(vim.tbl_map(vim.fn.shellescape, toggle_args), " "))
        code = vim.v.shell_error
      end
    end

    if code ~= 0 then
      n().error("git command failed")
    elseif skipped then
      n().info(name .. ".vim is now tracked in git")
    else
      n().info(name .. ".vim marked as skip-worktree (excluded from git)")
    end
  end, {
    nargs = "?",
    complete = function() return complete_names() end,
    desc = "Toggle git skip-worktree on a session file",
  })
end

return M
