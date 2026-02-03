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
    stack._reset()
  end)

  it("should start and stop the timer", function()
    cleanup.start()
    cleanup.stop()
    -- Should not error
  end)

  it("should update last_active_at on touch", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local model = stack.push(location)
    assert.is_not_nil(model)
    assert.is_not_nil(model.last_active_at)

    local before = model.last_active_at

    -- Wait a bit to ensure time has passed
    vim.wait(10)

    stack.touch(model.winid)

    -- Find the popup again to check updated time
    local items = stack.list()
    local found = nil
    for _, item in ipairs(items) do
      if item.winid == model.winid then
        found = item
        break
      end
    end

    assert.is_not_nil(found)
    local after = found.last_active_at
    assert.is_true(after >= before)
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

  it("should respect enabled setting", function()
    config.setup({
      ui = {
        popup = {
          auto_close = {
            enabled = false,
          },
        },
      },
    })

    cleanup.start()
    cleanup.scan(vim.uv.now())
    -- Should not error even when disabled
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
