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
end)
