describe("peekstack.core.events", function()
  local events = require("peekstack.core.events")
  local stack = require("peekstack.core.stack")
  local config = require("peekstack.config")

  local original_touch
  local original_close_ephemerals

  before_each(function()
    config.setup({
      ui = {
        quick_peek = { close_events = {} },
        popup = { auto_close = { enabled = false } },
      },
    })
    original_touch = stack.touch
    original_close_ephemerals = stack.close_ephemerals
  end)

  after_each(function()
    stack.touch = original_touch
    stack.close_ephemerals = original_close_ephemerals
    local winid = vim.api.nvim_get_current_win()
    vim.w[winid].peekstack_popup_id = nil
  end)

  it("skips non-peekstack windows on CursorMoved", function()
    local touch_calls = 0
    stack.touch = function()
      touch_calls = touch_calls + 1
    end
    stack.close_ephemerals = function() end

    local winid = vim.api.nvim_get_current_win()
    vim.w[winid].peekstack_popup_id = nil

    events.setup()
    vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })

    assert.equals(0, touch_calls)
  end)

  it("touches peekstack popup windows on CursorMoved", function()
    local touch_calls = 0
    stack.touch = function()
      touch_calls = touch_calls + 1
    end
    stack.close_ephemerals = function() end

    local winid = vim.api.nvim_get_current_win()
    vim.w[winid].peekstack_popup_id = 999

    events.setup()
    vim.api.nvim_exec_autocmds("WinEnter", { modeline = false })
    vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })

    assert.equals(1, touch_calls)
  end)

  it("registers CursorMoved autocmd only for popup buffers", function()
    local winid = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_get_current_buf()

    events.setup()
    local before = vim.api.nvim_get_autocmds({
      group = "PeekstackEvents",
      event = "CursorMoved",
      buffer = bufnr,
    })
    assert.equals(0, #before)

    vim.w[winid].peekstack_popup_id = 999
    vim.api.nvim_exec_autocmds("WinEnter", { modeline = false })

    local after = vim.api.nvim_get_autocmds({
      group = "PeekstackEvents",
      event = "CursorMoved",
      buffer = bufnr,
    })
    assert.equals(1, #after)
  end)

  it("stops cleanup timer when re-setup disables auto_close", function()
    local timer_store = require("peekstack.util.timer").get_store()

    config.setup({
      ui = {
        quick_peek = { close_events = {} },
        popup = {
          auto_close = {
            enabled = true,
            idle_ms = 300000,
            check_interval_ms = 60000,
            ignore_pinned = true,
          },
        },
      },
    })
    events.setup()
    assert.is_not_nil(timer_store.cleanup)

    config.setup({
      ui = {
        quick_peek = { close_events = {} },
        popup = { auto_close = { enabled = false } },
      },
    })
    events.setup()
    assert.is_nil(timer_store.cleanup)
  end)

  it("falls back to default close_events when quick_peek.close_events is invalid", function()
    config.setup({
      ui = {
        quick_peek = { close_events = "CursorMoved" },
        popup = { auto_close = { enabled = false } },
      },
    })

    assert.has_no.errors(function()
      events.setup()
    end)

    local buf_leave = vim.api.nvim_get_autocmds({
      group = "PeekstackEvents",
      event = "BufLeave",
    })
    local win_leave = vim.api.nvim_get_autocmds({
      group = "PeekstackEvents",
      event = "WinLeave",
    })

    assert.equals(1, #buf_leave)
    assert.equals(2, #win_leave)
  end)

  it("closes quick peek popups only for the current root window", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    config.setup({
      ui = {
        quick_peek = { close_events = { "CursorMoved" } },
        popup = { auto_close = { enabled = false } },
      },
    })
    events.setup()

    local left_win = vim.api.nvim_get_current_win()
    vim.api.nvim_cmd({ cmd = "vsplit" }, {})
    local right_win = vim.api.nvim_get_current_win()

    vim.api.nvim_set_current_win(left_win)
    local left_popup = stack.push(location, { stack = false })
    assert.is_not_nil(left_popup)

    vim.api.nvim_set_current_win(right_win)
    local right_popup = stack.push(location, { stack = false })
    assert.is_not_nil(right_popup)

    vim.api.nvim_set_current_win(left_win)
    vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })

    assert.is_nil(stack._ephemerals()[left_popup.id])
    assert.is_not_nil(stack._ephemerals()[right_popup.id])

    stack.close(right_popup.id)
    vim.api.nvim_cmd({ cmd = "only" }, {})
  end)
end)
