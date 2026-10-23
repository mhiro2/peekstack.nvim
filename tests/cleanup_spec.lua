describe("peekstack.core.cleanup", function()
  local cleanup = require("peekstack.core.cleanup")
  local stack = require("peekstack.core.stack")
  local config = require("peekstack.config")

  local function focus_normal_window()
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local cfg = vim.api.nvim_win_get_config(winid)
      if cfg.relative == "" then
        vim.api.nvim_set_current_win(winid)
        return
      end
    end
  end

  before_each(function()
    stack._reset()
    config.setup({
      ui = {
        popup = {
          auto_close = {
            enabled = true,
            idle_ms = 300000,
            check_interval_ms = 1000,
            ignore_pinned = true,
          },
        },
      },
    })
    focus_normal_window()
  end)

  after_each(function()
    cleanup.stop()
    -- stack._reset only clears state, so close the popups tests leave open.
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(winid).relative ~= "" then
        pcall(vim.api.nvim_win_close, winid, true)
      end
    end
    stack._reset()
  end)

  it("should scan periodically after start and stop scanning after stop", function()
    config.setup({
      ui = {
        popup = {
          auto_close = {
            enabled = true,
            idle_ms = 300000,
            check_interval_ms = 20,
            ignore_pinned = true,
          },
        },
      },
    })
    local timer_store = require("peekstack.util.timer").get_store()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local stale = stack.push(location)
    assert.is_not_nil(stale)
    stale.last_active_at = vim.uv.now() - 400000

    cleanup.start()
    local handle = timer_store.cleanup
    assert.is_not_nil(handle)
    assert.is_true(handle:is_active())
    assert.is_true(vim.wait(1000, function()
      return stack.find_by_id(stale.id) == nil
    end, 10))
    assert.is_false(vim.api.nvim_win_is_valid(stale.winid))

    -- A popup going stale after the first scan is closed by a later one.
    focus_normal_window()
    local later = stack.push(location)
    assert.is_not_nil(later)
    later.last_active_at = vim.uv.now() - 400000
    assert.is_true(vim.wait(1000, function()
      return stack.find_by_id(later.id) == nil
    end, 10))

    cleanup.stop()
    assert.is_nil(timer_store.cleanup)
    assert.is_true(handle:is_closing())

    focus_normal_window()
    local survivor = stack.push(location)
    assert.is_not_nil(survivor)
    survivor.last_active_at = vim.uv.now() - 400000
    -- Several intervals pass without a scan once the timer is stopped.
    vim.wait(100)
    assert.is_not_nil(stack.find_by_id(survivor.id))
  end)

  it("should update last_active_at on touch", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local model = stack.push(location)
    assert.is_not_nil(model)
    model.last_active_at = 0

    -- Touching a window that is not a popup leaves the popup untouched.
    focus_normal_window()
    stack.touch(vim.api.nvim_get_current_win())
    assert.equals(0, model.last_active_at)

    local before_touch = vim.uv.now()
    stack.touch(model.winid)

    local found = stack.find_by_id(model.id)
    assert.equals(model, found)
    assert.is_true(found.last_active_at >= before_touch)
    assert.is_true(found.last_active_at <= vim.uv.now())
  end)

  it("should close stale popups when idle_ms is exceeded", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local model = stack.push(location)
    assert.is_not_nil(model)

    -- Set last_active_at to a long time ago
    model.last_active_at = vim.uv.now() - 400000 -- more than idle_ms

    local now = vim.uv.now()
    stack.close_stale(now, { ignore_pinned = true })

    -- The popup should be closed
    local found = stack.find_by_id(model.id)
    assert.is_nil(found)
  end)

  it("should skip pinned popups when ignore_pinned is true", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local model = stack.push(location)
    assert.is_not_nil(model)
    model.pinned = true

    -- Set last_active_at to a long time ago
    model.last_active_at = (vim.uv.now()) - 400000

    local now = vim.uv.now()
    stack.close_stale(now, { ignore_pinned = true })

    -- The pinned popup should still be there
    local found = stack.find_by_id(model.id)
    assert.is_not_nil(found)
  end)

  it("should close pinned popups when ignore_pinned is false", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local model = stack.push(location)
    assert.is_not_nil(model)
    model.pinned = true
    model.last_active_at = (vim.uv.now()) - 400000

    local now = vim.uv.now()
    stack.close_stale(now, { ignore_pinned = false })

    local found = stack.find_by_id(model.id)
    assert.is_nil(found)
  end)

  it("should close popups when origin buffer is wiped", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local model = stack.push(location)
    assert.is_not_nil(model)

    local origin_bufnr = model.origin.bufnr

    -- Simulate origin wipeout
    stack.handle_origin_wipeout(origin_bufnr)

    -- The popup should be closed
    local found = stack.find_by_id(model.id)
    assert.is_nil(found)
  end)

  it("should handle scan safely when no popups exist", function()
    local now = vim.uv.now()
    cleanup.scan(now)
    -- Should not error
  end)

  it("should use vim.uv.now() as default when now_ms is omitted", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local model = stack.push(location)
    assert.is_not_nil(model)

    -- Set last_active_at to a long time ago (monotonic basis)
    model.last_active_at = vim.uv.now() - 400000

    -- Call scan without explicit now_ms — should default to vim.uv.now()
    cleanup.scan()

    -- The stale popup should be closed
    local found = stack.find_by_id(model.id)
    assert.is_nil(found)
  end)

  it("should neither start the timer nor close popups when disabled", function()
    config.setup({
      ui = {
        popup = {
          auto_close = {
            enabled = false,
            idle_ms = 1000,
            check_interval_ms = 20,
          },
        },
      },
    })
    local timer_store = require("peekstack.util.timer").get_store()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local model = stack.push(location)
    assert.is_not_nil(model)
    model.last_active_at = vim.uv.now() - 400000

    cleanup.start()
    assert.is_nil(timer_store.cleanup)

    cleanup.scan(vim.uv.now())
    vim.wait(100)
    assert.equals(model, stack.find_by_id(model.id))
    assert.is_true(vim.api.nvim_win_is_valid(model.winid))
  end)

  it("should not auto-close modified source-mode popup when prevent_auto_close_if_modified is true", function()
    config.setup({
      ui = {
        popup = {
          auto_close = {
            enabled = true,
            idle_ms = 300000,
            check_interval_ms = 1000,
            ignore_pinned = true,
          },
          source = {
            prevent_auto_close_if_modified = true,
          },
        },
      },
    })

    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local model = stack.push(location, { buffer_mode = "source" })
    assert.is_not_nil(model)
    assert.equals("source", model.buffer_mode)

    -- Mark buffer as modified
    vim.bo[model.bufnr].modified = true

    -- Set last_active_at to a long time ago
    model.last_active_at = vim.uv.now() - 400000

    local now = vim.uv.now()
    stack.close_stale(now, { ignore_pinned = true })

    -- The modified source popup should still be there
    local found = stack.find_by_id(model.id)
    assert.is_not_nil(found)

    -- Cleanup: unset modified to allow close
    vim.bo[model.bufnr].modified = false
    stack.close(model.id)
  end)

  it("should auto-close unmodified source-mode popup normally", function()
    config.setup({
      ui = {
        popup = {
          auto_close = {
            enabled = true,
            idle_ms = 300000,
            check_interval_ms = 1000,
            ignore_pinned = true,
          },
          source = {
            prevent_auto_close_if_modified = true,
          },
        },
      },
    })

    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local model = stack.push(location, { buffer_mode = "source" })
    assert.is_not_nil(model)

    -- Buffer is NOT modified
    model.last_active_at = vim.uv.now() - 400000

    local now = vim.uv.now()
    stack.close_stale(now, { ignore_pinned = true })

    -- The unmodified source popup should be closed
    local found = stack.find_by_id(model.id)
    assert.is_nil(found)
  end)
end)
