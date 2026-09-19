-- TESTS/run.lua — headless test runner for sessions.nvim.
--
-- Run from the repo root:
--   nvim --headless -u NONE -c "set rtp+=." -l TESTS/run.lua
--
-- lib.nvim has to be reachable: sessions.portable and several other modules
-- require it at module load. The runner puts a sibling checkout on the
-- runtimepath, or whatever $LIB_NVIM_PATH points at.

-- Absolute, and resolved before any spec runs: a spec may move the working
-- directory (git_spec resolves a branch from wherever Neovim stands), and a
-- relative `TESTS/` would then point at nothing for every spec after it.
local dir = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")) .. "/"

do
  local candidates = {}
  if vim.env.LIB_NVIM_PATH and vim.env.LIB_NVIM_PATH ~= "" then
    candidates[#candidates + 1] = vim.env.LIB_NVIM_PATH
  end
  candidates[#candidates + 1] = dir .. "../../lib.nvim"
  candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/lib.nvim"

  for _, path in ipairs(candidates) do
    local norm = vim.fs.normalize(path)
    if vim.fn.isdirectory(norm .. "/lua/lib") == 1 then
      vim.opt.rtp:append(norm)
      package.path = table.concat({
        norm .. "/lua/?.lua",
        norm .. "/lua/?/init.lua",
        package.path,
      }, ";")
      break
    end
  end
end

if not pcall(require, "lib.nvim.fs.read") then
  print("FAIL  cannot locate lib.nvim (a runtime dependency of sessions.nvim).")
  print("      Set $LIB_NVIM_PATH, or check it out next to this repo.")
  os.exit(1)
end

local H = dofile(dir .. "harness.lua")

-- Ordered so a failure points at the smallest layer first: pure functions,
-- then the storage layer, then core, then everything that wires core into
-- Neovim (commands, autocmds, keymaps, setup).
--
-- `statusline_spec` runs before `core_spec` on purpose -- it asserts what the
-- component renders with *no* session loaded, which is only true while no
-- earlier spec has left one active.
local specs = {
  "sanitize_spec.lua",
  "resolve_name_spec.lua",
  "git_spec.lua",
  "config_spec.lua",
  "state_spec.lua",
  "meta_spec.lua",
  "buforder_spec.lua",
  "portable_spec.lua",
  "layout_spec.lua",
  "statusline_spec.lua",
  "core_spec.lua",
  "marks_spec.lua",
  "picker_spec.lua",
  "health_spec.lua",
  "keymaps_spec.lua",
  "usercmds_spec.lua",
  "autocmds_spec.lua",
  "init_spec.lua",
}

local failed = 0
for _, name in ipairs(specs) do
  local run = dofile(dir .. name)
  local ok, err = pcall(run, H)
  if ok then
    print(("ok    %s"):format(name))
  else
    failed = failed + 1
    print(("FAIL  %s\n      %s"):format(name, tostring(err)))
  end
end

if failed > 0 then
  print(("\n%d spec(s) failed"):format(failed))
  os.exit(1)
end

print("\nSESSIONS_TESTS_OK")
