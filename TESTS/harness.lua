-- TESTS/harness.lua — tiny assertion helper shared by the spec files.
-- Returned to each spec by TESTS/run.lua.

local H = {}

--- This directory, absolute, resolved while the working directory is still
--- the one the runner was started from -- `H.fixture` must keep answering the
--- same path after a spec has moved `cwd` (see `H.fixture`).
local HERE = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h"))

--- Assert equality; raises a descriptive error on mismatch (caught by the runner).
---@param a any # actual
---@param b any # expected
---@param msg string|nil
function H.eq(a, b, msg)
  if a ~= b then
    error(("FAIL %s: expected %q, got %q"):format(msg or "", tostring(b), tostring(a)), 2)
  end
end

--- Assert a truthy value.
---@param v any
---@param msg string|nil
function H.ok(v, msg)
  if not v then
    error(("FAIL %s: expected truthy, got %q"):format(msg or "", tostring(v)), 2)
  end
end

--- Assert a falsy value.
---@param v any
---@param msg string|nil
function H.falsy(v, msg)
  if v then
    error(("FAIL %s: expected falsy, got %q"):format(msg or "", tostring(v)), 2)
  end
end

--- Assert that `haystack` contains `needle` as a literal substring.
---@param haystack string
---@param needle string
---@param msg string|nil
function H.contains(haystack, needle, msg)
  if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
    error(("FAIL %s: %q does not contain %q"):format(msg or "", tostring(haystack), needle), 2)
  end
end

--- Assert that `haystack` does NOT contain `needle`.
---@param haystack string
---@param needle string
---@param msg string|nil
function H.excludes(haystack, needle, msg)
  if type(haystack) == "string" and haystack:find(needle, 1, true) then
    error(("FAIL %s: %q still contains %q"):format(msg or "", tostring(haystack), needle), 2)
  end
end

--- A scratch directory inside the repository, removed by `cleanup()`.
---
--- Inside the repo rather than in `vim.fn.tempname()` on purpose: on Windows
--- the temp path carries an 8.3 short component (`STEFAN~1`), which several
--- Vim path builtins do not see through -- a fixture there would pass on Linux
--- and quietly assert nothing locally.
---
--- Anchored at this file's own directory rather than at `getcwd()`: a spec
--- that has to move the working directory (`git_spec` resolves a branch from
--- wherever Neovim happens to stand) would otherwise scatter its fixtures
--- into whatever directory it moved to, and clean up the wrong one.
---@param name string
---@return string dir, fun() cleanup
function H.fixture(name)
  local dir = HERE .. "/.fixture-" .. name
  vim.fn.delete(dir, "rf")
  vim.fn.mkdir(dir, "p")
  return dir, function()
    vim.fn.delete(dir, "rf")
  end
end

--- Replace a module for the duration of a test, or make it look uninstalled.
---
--- The seam every spec here uses instead of a real process or a real plugin:
--- `package.loaded` is swapped *before* the module under test requires it.
--- `false` means "not installed" -- clearing `package.loaded` alone is not
--- enough, since `require` would just load the real file again, so a
--- `package.preload` entry that raises stands in for the missing searcher and
--- makes the module's own `pcall(require, ...)` take its fallback branch.
---@param name string # module name as `require` spells it
---@param value table|function|false # replacement module, or `false` for "absent"
---@return fun() restore
function H.stub(name, value)
  local prev_loaded = package.loaded[name]
  local prev_preload = package.preload[name]

  if value == false then
    package.loaded[name] = nil
    package.preload[name] = function()
      error(("module '%s' not installed (test stub)"):format(name), 0)
    end
  else
    package.loaded[name] = value
  end

  return function()
    package.loaded[name] = prev_loaded
    package.preload[name] = prev_preload
  end
end

--- Require `name` with a cleared cache, so a module that resolves its soft
--- dependencies once at load time (`local ok = pcall(require, ...)`) sees
--- whatever `H.stub` has put in place right now.
---@param name string
---@return any
function H.fresh(name)
  package.loaded[name] = nil
  return require(name)
end

--- Read a file back as one string.
---@param path string
---@return string
function H.read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return ""
  end
  return table.concat(lines, "\n")
end

return H
