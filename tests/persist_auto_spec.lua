describe("peekstack.persist.auto", function()
  local auto = require("peekstack.persist.auto")
  local config = require("peekstack.config")
  local fs = require("peekstack.util.fs")
  local persist = require("peekstack.persist")
  local stack = require("peekstack.core.stack")

  local original_repo_root = nil
  local original_restore = nil
  local original_save = nil

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

    original_repo_root = fs.repo_root
    fs.repo_root = function()
      return "/tmp/peekstack-test-repo"
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
  end)

  it("restores when repo exists and stack is empty", function()
    local calls = 0
    original_restore = persist.restore
    persist.restore = function(name, opts)
      calls = calls + 1
      assert.equals("auto", name)
      assert.equals("repo", opts.scope)
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
end)
