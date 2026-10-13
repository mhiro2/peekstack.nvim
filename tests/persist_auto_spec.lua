describe("peekstack.persist.auto", function()
  local auto = require("peekstack.persist.auto")
  local config = require("peekstack.config")
  local fs = require("peekstack.util.fs")
  local persist = require("peekstack.persist")
  local stack = require("peekstack.core.stack")

  local original_repo_root = nil
  local original_restore = nil
  local original_save = nil
  local repo = "/tmp/peekstack-test-repo"

  ---@return { name: string, opts: table }[]
  local function capture_saves()
    local calls = {}
    original_save = persist.save_current
    persist.save_current = function(name, opts)
      calls[#calls + 1] = { name = name, opts = opts }
    end
    return calls
  end

  ---@param calls table[]
  ---@param count integer
  local function wait_for_saves(calls, count)
    local ok = vim.wait(200, function()
      return #calls == count
    end, 10)
    assert.is_true(ok, "Timed out waiting for " .. count .. " save(s)")
  end

  ---@param repo_dir string
  ---@return string
  local function store_path_for(repo_dir)
    return vim.fn.stdpath("state") .. "/peekstack/repo_" .. fs.slug(repo_dir) .. ".json"
  end

  before_each(function()
    stack._reset()
    auto._reset()
    config.setup({
      persist = {
        enabled = true,
        auto = {
          enabled = true,
          session_name = "auto",
          restore = true,
          save = true,
          restore_if_empty = true,
          debounce_ms = 20,
          save_on_leave = true,
        },
      },
    })

    repo = "/tmp/peekstack-test-repo"
    original_repo_root = fs.repo_root
    fs.repo_root = function()
      return repo
    end
  end)

  after_each(function()
    if original_repo_root then
      fs.repo_root = original_repo_root
    end
    if original_restore then
      persist.restore = original_restore
    end
    if original_save then
      persist.save_current = original_save
    end
    original_repo_root = nil
    original_restore = nil
    original_save = nil
    auto._reset()
    stack._reset()
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
  end)

  it("restores when repo exists and stack is empty", function()
    local calls = 0
    original_restore = persist.restore
    persist.restore = function(name, opts)
      calls = calls + 1
      assert.equals("auto", name)
      assert.is_true(opts.silent)
    end

    local restored = auto.maybe_restore()
    assert.is_true(restored)
    assert.equals(1, calls)
  end)

  it("does not restore when stack is not empty", function()
    local calls = 0
    original_restore = persist.restore
    persist.restore = function()
      calls = calls + 1
    end

    local s = stack.current_stack(vim.api.nvim_get_current_win())
    s.popups = {
      {
        id = 1,
        location = {
          uri = "file:///tmp/test.lua",
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
          provider = "test",
        },
        title = "Test",
      },
    }

    local restored = auto.maybe_restore()
    assert.is_false(restored)
    assert.equals(0, calls)
  end)

  it("debounces save calls", function()
    local calls = 0
    original_save = persist.save_current
    persist.save_current = function()
      calls = calls + 1
    end

    auto.schedule_save({ root_winid = vim.api.nvim_get_current_win() })
    auto.schedule_save({ root_winid = vim.api.nvim_get_current_win() })

    local ok = vim.wait(200, function()
      return calls == 1
    end, 10)
    assert.is_true(ok, "Timed out waiting for debounced save")
  end)

  it("uses synchronous save on VimLeavePre path", function()
    local calls = 0
    original_save = persist.save_current
    persist.save_current = function(name, opts)
      calls = calls + 1
      assert.equals("auto", name)
      assert.is_true(opts.silent)
      assert.is_true(opts.sync)
    end

    local saved = auto.save_on_leave({ root_winid = vim.api.nvim_get_current_win() })
    assert.is_true(saved)
    assert.equals(1, calls)
  end)

  it("saves to the store resolved when the save was scheduled", function()
    local calls = capture_saves()

    auto.schedule_save({ root_winid = vim.api.nvim_get_current_win() })
    repo = "/tmp/peekstack-test-other-repo"

    wait_for_saves(calls, 1)
    assert.equals(store_path_for("/tmp/peekstack-test-repo"), calls[1].opts.store_path)
  end)

  it("flushes a pending save before scheduling one for another store", function()
    local calls = capture_saves()
    local winid = vim.api.nvim_get_current_win()

    auto.schedule_save({ root_winid = winid })
    repo = "/tmp/peekstack-test-other-repo"
    auto.schedule_save({ root_winid = winid })

    wait_for_saves(calls, 2)
    assert.equals(store_path_for("/tmp/peekstack-test-repo"), calls[1].opts.store_path)
    assert.equals(store_path_for("/tmp/peekstack-test-other-repo"), calls[2].opts.store_path)
  end)

  it("flushes a pending save before scheduling one for another stack", function()
    local calls = capture_saves()
    local first = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local second = vim.api.nvim_get_current_win()

    auto.schedule_save({ root_winid = first })
    auto.schedule_save({ root_winid = second })

    wait_for_saves(calls, 2)
    assert.equals(first, calls[1].opts.root_winid)
    assert.equals(second, calls[2].opts.root_winid)
  end)

  it("saves the stack of the window that changed after a tab switch", function()
    local calls = capture_saves()
    local winid = vim.api.nvim_get_current_win()

    auto.schedule_save({ root_winid = winid })
    vim.cmd("tabnew")

    wait_for_saves(calls, 1)
    assert.equals(winid, calls[1].opts.root_winid)
  end)

  it("saves the tracked stack on leave from another split", function()
    local calls = capture_saves()
    local winid = vim.api.nvim_get_current_win()

    auto.schedule_save({ root_winid = winid })
    wait_for_saves(calls, 1)

    vim.cmd("vsplit")
    assert.are_not.equal(winid, vim.api.nvim_get_current_win())
    repo = "/tmp/peekstack-test-other-repo"

    assert.is_true(auto.save_on_leave())
    assert.equals(2, #calls)
    assert.equals(winid, calls[2].opts.root_winid)
    assert.equals(store_path_for("/tmp/peekstack-test-repo"), calls[2].opts.store_path)
    assert.is_true(calls[2].opts.sync)
  end)

  it("saves a pending stack synchronously on leave", function()
    local calls = capture_saves()
    local winid = vim.api.nvim_get_current_win()

    auto.schedule_save({ root_winid = winid })
    vim.cmd("vsplit")

    assert.is_true(auto.save_on_leave())
    assert.equals(1, #calls)
    assert.equals(winid, calls[1].opts.root_winid)
    assert.is_true(calls[1].opts.sync)

    vim.wait(60, function()
      return false
    end, 10)
    assert.equals(1, #calls)
  end)

  it("does not save on leave when no stack changed", function()
    local calls = capture_saves()
    assert.is_false(auto.save_on_leave())
    assert.equals(0, #calls)
  end)

  it("does not save a stack whose root window was closed", function()
    local calls = capture_saves()
    vim.cmd("vsplit")
    local closing = vim.api.nvim_get_current_win()

    auto.schedule_save({ root_winid = closing })
    vim.api.nvim_win_close(closing, true)

    vim.wait(60, function()
      return false
    end, 10)
    assert.equals(0, #calls)
    assert.is_false(auto.save_on_leave())
    assert.equals(0, #calls)
    assert.is_false(auto.schedule_save({ root_winid = closing }))
  end)

  describe("with real popups and store", function()
    local store = require("peekstack.persist.store")
    local temp_file = nil

    ---@param winid? integer
    ---@param opts? table
    ---@return PeekstackPopupModel
    local function push_popup(winid, opts)
      local model = stack.push({
        uri = vim.uri_from_fname(temp_file),
        range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 1 } },
        provider = "test",
      }, vim.tbl_extend("force", { root_winid = winid }, opts or {}))
      assert.is_not_nil(model)
      return model
    end

    ---@return PeekstackSessionItem[]?
    local function saved_items()
      local data = store.read_sync(store_path_for(repo))
      local session = data and data.sessions.auto
      return session and session.items or nil
    end

    ---@param count integer
    local function wait_for_saved_items(count)
      local ok = vim.wait(500, function()
        local items = saved_items()
        return items ~= nil and #items == count
      end, 10)
      assert.is_true(ok, "Timed out waiting for " .. count .. " saved item(s)")
    end

    local function settle()
      vim.wait(80, function()
        return false
      end, 10)
    end

    before_each(function()
      persist._reset_cache()
      vim.fn.delete(store_path_for(repo))
      temp_file = vim.fn.tempname() .. ".lua"
      vim.fn.writefile({ "line1", "line2", "line3" }, temp_file)
    end)

    after_each(function()
      vim.api.nvim_create_augroup("PeekstackPersistAuto", { clear = true })
      pcall(stack.close_ephemerals)
      stack._reset()
      vim.fn.delete(store_path_for(repo))
      if temp_file then
        vim.fn.delete(temp_file)
      end
      persist._reset_cache()
    end)

    it("keeps the saved session when a quick peek opens and closes elsewhere", function()
      auto.setup()
      local first = vim.api.nvim_get_current_win()
      push_popup(first)
      wait_for_saved_items(1)

      vim.api.nvim_set_current_win(first)
      vim.cmd("vsplit")
      local second = vim.api.nvim_get_current_win()
      local quick = push_popup(second, { stack = false })
      assert.is_true(quick.ephemeral)
      settle()
      stack.close(quick.id)
      settle()

      assert.equals(1, #stack.list(first))
      assert.equals(0, #stack.list(second))
      assert.equals(1, #saved_items())
    end)

    it("saves on leave when only save_on_leave is enabled", function()
      config.setup({
        persist = {
          enabled = true,
          auto = { enabled = true, restore = false, save = false, save_on_leave = true, debounce_ms = 20 },
        },
      })
      auto.setup()
      push_popup(vim.api.nvim_get_current_win())
      settle()
      assert.is_nil(saved_items())

      vim.cmd("vsplit")
      vim.api.nvim_exec_autocmds("VimLeavePre", { group = "PeekstackPersistAuto" })
      assert.equals(1, #saved_items())
    end)

    it("does not save on leave when only debounced saves are enabled", function()
      config.setup({
        persist = {
          enabled = true,
          auto = { enabled = true, restore = false, save = true, save_on_leave = false, debounce_ms = 20 },
        },
      })
      auto.setup()
      local winid = vim.api.nvim_get_current_win()
      push_popup(winid)
      wait_for_saved_items(1)

      push_popup(winid)
      vim.api.nvim_exec_autocmds("VimLeavePre", { group = "PeekstackPersistAuto" })
      assert.equals(1, #saved_items())
    end)
  end)
end)
