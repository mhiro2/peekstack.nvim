describe("peekstack.core.events", function()
  local events = require("peekstack.core.events")
  local stack = require("peekstack.core.stack")
  local config = require("peekstack.config")

  local original_touch
  local original_close_ephemerals
  local original_win_get_config

  before_each(function()
    config.setup({
      ui = {
        quick_peek = { close_events = {} },
        popup = { auto_close = { enabled = false } },
      },
    })
    original_touch = stack.touch
    original_close_ephemerals = stack.close_ephemerals
    original_win_get_config = vim.api.nvim_win_get_config
  end)

  after_each(function()
    stack.touch = original_touch
    stack.close_ephemerals = original_close_ephemerals
    vim.api.nvim_win_get_config = original_win_get_config
    local winid = vim.api.nvim_get_current_win()
    vim.w[winid].peekstack_popup_id = nil
  end)

  it("skips non-peekstack windows on CursorMoved", function()
    local touch_calls = 0
    local config_calls = 0
    stack.touch = function()
      touch_calls = touch_calls + 1
    end
    stack.close_ephemerals = function() end
    vim.api.nvim_win_get_config = function(winid)
      config_calls = config_calls + 1
      return original_win_get_config(winid)
    end

    local winid = vim.api.nvim_get_current_win()
    vim.w[winid].peekstack_popup_id = nil

    events.setup()
    vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })

    assert.equals(0, touch_calls)
    assert.equals(0, config_calls)
  end)

  it("touches peekstack popup windows on CursorMoved", function()
    local touch_calls = 0
    local config_calls = 0
    stack.touch = function()
      touch_calls = touch_calls + 1
    end
    stack.close_ephemerals = function() end
    vim.api.nvim_win_get_config = function()
      config_calls = config_calls + 1
      return { relative = "editor" }
    end

    local winid = vim.api.nvim_get_current_win()
    vim.w[winid].peekstack_popup_id = 999

    events.setup()
    vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })

    assert.equals(1, touch_calls)
    assert.equals(1, config_calls)
  end)
end)
