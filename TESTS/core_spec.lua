-- Test code: a fixture read or a metadata sidecar coming back nil here must
-- crash and name itself rather than be guarded away.
---@diagnostic disable: need-check-nil
-- TESTS/core_spec.lua — sessions.core: the whole save/load/list/delete/rename
-- surface, plus the two resolution rules everything else depends on.
--
-- Real sessions on disk, written by Neovim's own `:mksession` into a fixture
-- root and sourced back. The one thing that is stubbed is `sessions.git`:
-- core only requires it when `branch_aware`/`project_aware` ask it to, and
-- what a *checkout* happens to be called or be branched on is not what these
-- assertions are about (git_spec.lua covers the real resolution).

return function(H)
  local core = require("sessions.core")
  local config = require("sessions.config")
  local api = vim.api

  local dir, cleanup = H.fixture("core")
  local root = dir .. "/sroot"
  local saved_sessionoptions = vim.o.sessionoptions

  -- Start from no buffers: `:mksession` records whatever is open, and an
  -- earlier spec's fixture files (already deleted by its cleanup) would be
  -- written into every session this spec saves and then complained about
  -- ("E211: File … no longer available") on every load.
  vim.cmd("silent! %bwipeout!")

  ---Configure sessions with a fixture root and everything optional off,
  ---then apply `extra` on top.
  ---@param extra table|nil
  ---@return Sessions.Config
  local function setup(extra)
    config.setup(vim.tbl_deep_extend("force", {
      root = root,
      branch_aware = false,
      project_aware = false,
      metadata = false,
      restore_buffer_order = false,
      autosave = false,
    }, extra or {}))
    return config.get()
  end

  ---@param name string
  ---@return string
  local function session_file(name)
    return config.get().root .. "/" .. name .. ".vim"
  end

  -- ------------------------------------------------------------ list, empty

  setup()
  H.eq(#core.list(), 0, "a root that does not exist yet lists no sessions")
  H.eq(#core.list_tabs(), 0, "and no tab sessions either")
  H.falsy(core.metadata("nothing"), "metadata for a session that was never saved is nothing")

  -- ------------------------------------------------------- save, the basics

  local ok, path = core.save("alpha")
  H.ok(ok, "save reports success")
  H.eq(path, session_file("alpha"), "returning the file it wrote")
  H.eq(vim.fn.filereadable(path), 1, "which exists")
  H.contains(H.read(path), "let SessionLoad = 1", "and is a Vim session file")
  H.eq(core.current(), "alpha", "the saved session becomes the current one")

  -- A save is as much "resume this next" as an explicit load: without it the
  -- very first save in a project could not be found again by a bare
  -- `:Session load`, which would fall back to another project's pointer.
  H.eq(
    require("sessions.state").read(config.get()).last_loaded,
    "alpha",
    "and is remembered as the last-loaded session"
  )

  -- dirty tracking ------------------------------------------------------------
  H.falsy(core.dirty(), "a freshly saved session is not dirty")
  core.mark_dirty()
  H.ok(core.dirty(), "a structural change marks it dirty")
  core.save("alpha")
  H.falsy(core.dirty(), "and saving clears that again")

  -- metadata = false means no sidecar at all, not an empty one.
  H.eq(vim.fn.filereadable(config.get().root .. "/.alpha.json"), 0, "metadata = false writes none")
  H.falsy(core.metadata("alpha"), "so there is nothing to read back")

  -- ---------------------------------------------------------------- metadata

  do
    local git_stub = H.stub("sessions.git", {
      resolve_name = function()
        return "autoname"
      end,
      current_branch = function()
        return "meta-branch"
      end,
    })
    setup({ metadata = true, branch_aware = true })

    H.ok(core.save("beta"))
    local meta = core.metadata("beta")
    H.ok(meta, "metadata = true writes a sidecar")
    H.eq(meta.branch, "meta-branch", "carrying the branch it was saved on")
    H.eq(meta.cwd, vim.fn.getcwd(), "and the cwd")
    H.ok(meta.saved_at:match("^%d%d%d%d%-%d%d%-%d%dT"), "and an ISO-8601 timestamp")
    H.eq(type(meta.buffers), "table", "and the list of open buffers")

    git_stub()
    setup()
  end

  -- ------------------------------------------------------------------- list

  H.ok(core.save("gamma"))
  local listed = core.list()
  H.eq(#listed, 3, "every saved session is listed")
  local names = vim.tbl_map(function(p)
    return vim.fn.fnamemodify(p, ":t:r")
  end, listed)
  H.eq(table.concat(names, ","), "alpha,beta,gamma", "sorted, and by name")
  -- The sidecars live in the same directory on purpose (hidden, dot-prefixed);
  -- listing must not mistake one for a session.
  H.excludes(table.concat(listed, "|"), ".beta.json", "sidecars are not sessions")
  H.excludes(table.concat(listed, "|"), ".state.json", "and neither is the state file")

  -- ------------------------------------------------------- blacklisted buffers

  do
    local junk_dir = dir .. "/junkdir"
    vim.fn.mkdir(junk_dir, "p")
    local junk_file = junk_dir .. "/secret.lua"
    vim.fn.writefile({ "-- junk" }, junk_file)
    local commit_file = dir .. "/COMMIT_EDITMSG"
    vim.fn.writefile({ "wip" }, commit_file)

    setup({
      blacklist = {
        buftypes = { "nofile" },
        filetypes = { "gitcommit" },
        -- Both separators: the prefix compare only ever matches the exact
        -- spelling a buffer name carries, and which one that is depends on
        -- how the buffer was opened (see config_spec.lua's %TEMP% block).
        paths = { junk_dir, (junk_dir:gsub("/", "\\")) },
      },
    })

    ---`bufadd` creates an *unlisted* buffer, and `:mksession` records only
    ---listed ones -- without this the "it is not in the file" assertions
    ---below would hold for the wrong reason.
    ---@param p string
    ---@return integer
    local function listed_buf(p)
      local b = vim.fn.bufadd(p)
      vim.fn.bufload(b)
      vim.bo[b].buflisted = true
      return b
    end

    local by_path = listed_buf(junk_file)
    local by_ft = listed_buf(commit_file)
    vim.bo[by_ft].filetype = "gitcommit"
    local by_buftype = api.nvim_create_buf(true, false)
    vim.fn.bufload(by_buftype)
    vim.bo[by_buftype].buftype = "nofile"

    local keeper = dir .. "/keepme.lua"
    vim.fn.writefile({ "-- keep" }, keeper)
    local kept = listed_buf(keeper)

    H.ok(core.save("clean"))

    H.falsy(api.nvim_buf_is_valid(by_path), "a buffer under a blacklisted path is wiped")
    H.falsy(api.nvim_buf_is_valid(by_ft), "and one with a blacklisted filetype")
    H.falsy(api.nvim_buf_is_valid(by_buftype), "and one with a blacklisted buftype")
    H.ok(api.nvim_buf_is_valid(kept), "an ordinary buffer is left alone")

    local content = H.read(session_file("clean"))
    H.excludes(content, "secret.lua", "the blacklisted path never reaches the session file")
    H.excludes(content, "COMMIT_EDITMSG", "nor the commit message buffer")
    H.contains(content, "keepme.lua", "while the ordinary buffer is recorded")

    core.delete("clean")
    api.nvim_buf_delete(kept, { force = true })
    setup()
  end

  -- --------------------------------------------------------- resolution order

  do
    -- Two candidates for a bare `:Session load`: the name this project/branch
    -- resolves to right now, and the globally remembered last-loaded one. The
    -- auto-resolved one must win -- `.state.json` is shared by every project,
    -- so preferring it meant opening project B could silently restore
    -- project A's session.
    local git_stub = H.stub("sessions.git", {
      resolve_name = function()
        return "autoname"
      end,
      current_branch = function()
        return nil
      end,
    })
    setup({ branch_aware = true, project_aware = true })

    require("sessions.state").set_last_loaded(config.get(), "gamma")

    local peeked, exists = core.peek()
    H.eq(peeked.name, "gamma", "with no auto-resolved session saved, the remembered one is used")
    H.ok(exists, "and it exists")

    H.ok(core.save("autoname"), "now save the project's own session")
    require("sessions.state").set_last_loaded(config.get(), "gamma")
    peeked, exists = core.peek()
    H.eq(peeked.name, "autoname", "the project's own session wins over the global pointer")
    H.ok(exists)

    -- Neither candidate available: default_name, which may well not exist yet.
    vim.fn.delete(session_file("autoname"))
    require("sessions.state").set_last_loaded(config.get(), "vanished")
    peeked, exists = core.peek()
    H.eq(peeked.name, config.get().default_name, "with neither, default_name is the target")
    H.falsy(exists, "and peek reports that there is nothing there")

    -- An auto-resolver that just gives back default_name is not a candidate:
    -- it carries no project information, so the remembered pointer is better.
    git_stub()
    local default_stub = H.stub("sessions.git", {
      resolve_name = function()
        return config.get().default_name
      end,
      current_branch = function()
        return nil
      end,
    })
    require("sessions.state").set_last_loaded(config.get(), "gamma")
    peeked = core.peek()
    H.eq(peeked.name, "gamma", "an auto-resolved default_name does not outrank the pointer")
    default_stub()

    setup()
  end

  -- ------------------------------------------------------------------- load

  do
    local bad_ok, bad_err = core.load("does-not-exist")
    H.falsy(bad_ok, "loading a session that is not there fails")
    H.contains(bad_err, "no such session:", "with a message naming the path")

    -- A modified, unnamed buffer cannot be written by the session and is
    -- reported back so the caller can warn about it.
    vim.cmd("enew")
    api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved work" })
    H.ok(vim.bo.modified, "the fixture buffer is modified")

    local load_ok, load_path, hidden = core.load("gamma")
    H.ok(load_ok, "load reports success")
    H.eq(load_path, session_file("gamma"), "naming the file it sourced")
    H.eq(type(hidden), "table", "and returns the modified buffers it had to hide")
    H.ok(#hidden > 0, "the unsaved buffer is among them")
    H.eq(core.current(), "gamma", "the loaded session is now the current one")
    H.falsy(core.dirty(), "and is not dirty")

    -- A session file that is not sourceable fails with the error rather than
    -- leaving the caller thinking it loaded.
    vim.fn.writefile({ "this is not vimscript at all" }, session_file("broken"))
    local broken_ok, broken_err = core.load("broken")
    H.falsy(broken_ok, "an unsourceable session file fails")
    H.ok(broken_err and #broken_err > 0, "with the error Vim raised")
    core.delete("broken")

    vim.cmd("silent! %bwipeout!")
  end

  -- ------------------------------------------------------------------ hooks

  do
    local seen = {}
    setup({
      hooks = {
        on_save = function(name, p)
          seen.save = name .. "|" .. p
        end,
        on_load = function(name, p)
          seen.load = name .. "|" .. p
        end,
      },
    })
    H.ok(core.save("hooked"))
    H.eq(seen.save, "hooked|" .. session_file("hooked"), "on_save gets the name and the path")
    H.ok(core.load("hooked"))
    H.eq(seen.load, "hooked|" .. session_file("hooked"), "on_load too")

    -- A user hook that raises must not turn a successful save into a failure:
    -- the session is already on disk by then.
    setup({
      hooks = {
        on_save = function()
          error("hook blew up")
        end,
      },
    })
    local hook_ok = core.save("hooked")
    H.ok(hook_ok, "a raising hook does not fail the save")
    core.delete("hooked")
    setup()
  end

  -- -------------------------------------------------------- relative_paths

  do
    setup({ relative_paths = true })
    H.ok(core.save("portable"))
    local content = H.read(session_file("portable"))
    H.contains(content, "{{SESSION_ROOT}}", "relative_paths rewrites the cwd to a placeholder")
    H.excludes(content, vim.fs.normalize(vim.fn.getcwd()), "so the file does not pin this machine")

    -- And it still loads: prepare_for_load re-anchors the placeholder into a
    -- temporary copy, leaving the stored file portable.
    H.ok(core.load("portable"), "a placeholder session still loads")
    H.contains(
      H.read(session_file("portable")),
      "{{SESSION_ROOT}}",
      "and the stored file keeps its placeholder"
    )
    core.delete("portable")
    setup()
    vim.cmd("silent! %bwipeout!")
  end

  -- --------------------------------------------------------- delete, rename

  do
    setup({ metadata = true })
    H.ok(core.save("victim"))
    H.ok(core.metadata("victim"), "the session has a metadata sidecar")

    local del_miss, del_miss_err = core.delete("not-there")
    H.falsy(del_miss, "deleting a session that is not there fails")
    H.contains(del_miss_err, "session not found:", "with a reason")

    H.eq(core.current(), "victim", "the session is the current one before deleting it")
    local del_ok, del_path = core.delete("victim")
    H.ok(del_ok, "delete reports success")
    H.eq(del_path, session_file("victim"), "naming the file it removed")
    H.eq(vim.fn.filereadable(del_path), 0, "the session file is gone")
    H.eq(vim.fn.filereadable(config.get().root .. "/.victim.json"), 0, "and so is its sidecar")
    H.falsy(core.current(), "deleting the active session clears the current one")

    -- rename ------------------------------------------------------------------
    H.ok(core.save("old"))
    H.falsy(core.rename("missing", "whatever"), "renaming a session that is not there fails")

    H.ok(core.save("occupied"))
    local clash_ok, clash_err = core.rename("old", "occupied")
    H.falsy(clash_ok, "renaming onto an existing name is refused")
    H.contains(clash_err, "session already exists:", "rather than overwriting it")

    core.save("old") -- make `old` the current session again
    local ren_ok, ren_path = core.rename("old", "new")
    H.ok(ren_ok, "rename reports success")
    H.eq(ren_path, session_file("new"), "naming the new file")
    H.eq(vim.fn.filereadable(session_file("old")), 0, "the old file is gone")
    H.eq(vim.fn.filereadable(ren_path), 1, "the new one is there")
    H.ok(core.metadata("new"), "the sidecar moved with it")
    H.falsy(core.metadata("old"), "and is no longer under the old name")
    H.eq(core.current(), "new", "renaming the active session renames the current one too")

    -- Noted rather than flagged: a rename does not follow the remembered
    -- last-loaded pointer, so until the next save a bare `:Session load` (and
    -- autoload) looks for a session that no longer exists and falls back to
    -- `default_name`. Saving is the very next thing most workflows do, which
    -- is why this is pinned as behaviour and not as a defect.
    H.eq(
      require("sessions.state").read(config.get()).last_loaded,
      "old",
      "the remembered pointer still names the session under its old name"
    )

    core.delete("new")
    core.delete("occupied")
    setup()
  end

  -- ------------------------------------------------------------ tab sessions

  do
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! only!")
    local tabs_before = #api.nvim_list_tabpages()

    H.falsy(core.load_tab(""), "a tab session needs a name")
    ---@diagnostic disable-next-line: param-type-mismatch
    local _, name_err = core.load_tab(nil)
    H.eq(name_err, "tab session name required", "and says so")
    local miss_ok, miss_err = core.load_tab("nope")
    H.falsy(miss_ok, "loading a tab session that is not there fails")
    H.contains(miss_err, "no such tab session:", "with a reason")

    -- A second tab, so "only this tab was captured" is a real claim: with
    -- `tabpages` still in sessionoptions, :mksession would write a `tabnew`
    -- line for it. The windows show a real file because `blank` is not in the
    -- configured sessionoptions -- a window on an empty unnamed buffer is not
    -- recorded at all, and the snapshot would hold no split to assert on.
    local tabfile = dir .. "/tabfile.lua"
    vim.fn.writefile({ "-- tab" }, tabfile)
    vim.cmd("tabnew " .. vim.fn.fnameescape(tabfile))
    vim.cmd("vsplit")
    local tab_ok, tab_path = core.save_tab("t1")
    H.ok(tab_ok, "save_tab reports success")
    H.eq(tab_path, config.get().root .. "/.tabs/t1.vim", "storing under <root>/.tabs/")
    H.eq(
      vim.o.sessionoptions,
      config.get().sessionoptions,
      "and puts sessionoptions back afterwards -- `tabpages` is dropped for that one save only"
    )
    local snapshot = H.read(tab_path)
    H.excludes(snapshot, "tabnew", "the snapshot holds no other tab")
    H.contains(snapshot, "vsplit", "but does hold this tab's split")
    vim.cmd("tabclose")
    H.eq(#api.nvim_list_tabpages(), tabs_before, "back to where the block started")

    -- A tab session is deliberately invisible to the normal session list.
    H.eq(#core.list_tabs(), 1, "list_tabs sees it")
    H.excludes(table.concat(core.list(), "|"), "t1.vim", "while list() does not")

    -- Unlike a full load, this one leaves the other tabs alone.
    H.ok(core.load_tab("t1"), "load_tab reports success")
    H.eq(#api.nvim_list_tabpages(), tabs_before + 1, "restoring a tab session opens a new tab")
    vim.cmd("tabclose")

    -- A snapshot that will not source closes the tab it just opened again,
    -- rather than leaving an empty one behind.
    vim.fn.writefile({ "this is not vimscript at all" }, config.get().root .. "/.tabs/bad.vim")
    local bad_ok = core.load_tab("bad")
    H.falsy(bad_ok, "an unsourceable tab snapshot fails")
    H.eq(#api.nvim_list_tabpages(), tabs_before, "and the tab it opened is closed again")

    vim.cmd("silent! only!")
  end

  -- ------------------------------------------------------- an unwritable root

  do
    local blocker = dir .. "/blocker"
    vim.fn.writefile({ "i am a file, not a directory" }, blocker)
    setup({ root = blocker })

    H.eq(#core.list(), 0, "a root that is not a directory lists nothing")

    -- Regression: `M.save` promises `(boolean ok, string|nil path_or_err)` and
    -- every caller reports the second value as "save failed: …". The
    -- `:mksession` call was pcall'd accordingly, but `ensure_dir()` above it
    -- was not, so a root that cannot be created (a file in the way, a
    -- read-only volume, a path component that is itself a file) used to
    -- escape as a raw `E739: Cannot create directory` -- including from the
    -- VimLeavePre autosave, where it surfaced as an error traceback while
    -- Neovim was quitting. `ensure_dir` now returns `(ok, err)` and both
    -- `save`/`save_tab` report it through the same contract as every other
    -- failure, instead of raising.
    local pcall_ok, save_ok, save_err = pcall(core.save, "nope")
    H.ok(pcall_ok, "an uncreatable root no longer raises")
    H.falsy(save_ok, "…save() itself reports failure")
    H.ok(save_err and save_err ~= "", "…with a message, not a bare false")

    local tab_pcall_ok, tab_ok, tab_err = pcall(core.save_tab, "nope")
    H.ok(tab_pcall_ok, "save_tab no longer raises, for the same reason")
    H.falsy(tab_ok, "…and reports failure the same way")
    H.ok(tab_err and tab_err ~= "", "…with a message too")
  end

  -- Leave no session active: statusline_spec's premise (and any later spec's)
  -- is that a headless run has none.
  setup()
  for _, p in ipairs(core.list()) do
    core.delete(vim.fn.fnamemodify(p, ":t:r"))
  end
  H.falsy(core.current(), "the spec leaves no session behind")

  config.setup({})
  vim.o.sessionoptions = saved_sessionoptions
  vim.cmd("silent! %bwipeout!")
  cleanup()
end
