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
end)
