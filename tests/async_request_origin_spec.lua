local peekstack = require("peekstack")
local registry = require("peekstack.registry")
local stack = require("peekstack.core.stack")
local config = require("peekstack.config")
local helpers = require("tests.helpers")

describe("async request origin", function()
  local win_a, win_b

  ---@param line integer
  ---@return PeekstackLocation
  local function location_at(line)
    return helpers.make_location({
      range = { start = { line = line, character = 0 }, ["end"] = { line = line, character = 0 } },
    })
  end

  before_each(function()
    stack._reset()
    config.setup({})
    vim.cmd("silent! only")
    win_a = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    win_b = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(win_a)
  end)

  after_each(function()
    for _, winid in ipairs({ win_a, win_b }) do
      if vim.api.nvim_win_is_valid(winid) then
        local popups = stack.list(winid)
        for i = #popups, 1, -1 do
          stack.close(popups[i].id)
        end
      end
    end
    stack._reset()
    vim.cmd("silent! only")
  end)

  it("pushes provider results onto the stack of the requesting window", function()
    local resolve
    peekstack.register_provider("test.async_origin", function(_ctx, cb)
      resolve = cb
    end)

    peekstack.peek("test.async_origin", {})

    -- The user moves to another window while the provider is still pending.
    vim.api.nvim_set_current_win(win_b)
    resolve({ location_at(2) })

    assert.equals(1, #stack.list(win_a))
    assert.equals(0, #stack.list(win_b))
  end)

  it("pushes picker results onto the stack of the requesting window", function()
    local resolve
    peekstack.register_provider("test.async_origin_multi", function(_ctx, cb)
      resolve = cb
    end)

    local builtin = registry.get_picker("builtin")
    local choose
    registry.register_picker("builtin", {
      pick = function(_locations, _opts, on_choice)
        choose = on_choice
      end,
    })

    peekstack.peek("test.async_origin_multi", {})
    resolve({ location_at(1), location_at(2) })

    -- The user moves away before answering the picker.
    vim.api.nvim_set_current_win(win_b)
    choose(location_at(2))

    registry.register_picker("builtin", builtin)

    assert.equals(1, #stack.list(win_a))
    assert.equals(0, #stack.list(win_b))
  end)

  it("drops provider results when the requesting window is gone", function()
    local resolve
    peekstack.register_provider("test.async_origin_closed", function(_ctx, cb)
      resolve = cb
    end)

    peekstack.peek("test.async_origin_closed", {})

    vim.api.nvim_win_close(win_a, true)
    resolve({ location_at(2) })

    assert.equals(0, #stack.list(win_b))
  end)

  it("keeps the frozen root and drops the parent when the source popup is gone", function()
    local parent = stack.push(location_at(1), {})
    assert.is_not_nil(parent)
    vim.api.nvim_set_current_win(parent.winid)

    local resolve
    peekstack.register_provider("test.async_origin_nested", function(_ctx, cb)
      resolve = cb
    end)
    peekstack.peek("test.async_origin_nested", {})

    stack.close(parent.id)
    vim.api.nvim_set_current_win(win_b)
    resolve({ location_at(3) })

    local popups = stack.list(win_a)
    assert.equals(1, #popups)
    assert.is_nil(popups[1].parent_popup_id)
    assert.equals(0, #stack.list(win_b))
  end)

  it("drops provider results when the user switched to another tabpage", function()
    local resolve
    peekstack.register_provider("test.async_origin_tab", function(_ctx, cb)
      resolve = cb
    end)

    peekstack.peek("test.async_origin_tab", {})

    vim.cmd("tabnew")
    local other_tab_win = vim.api.nvim_get_current_win()
    resolve({ location_at(2) })

    assert.equals(0, #stack.list(win_a))
    assert.equals(0, #stack.list(other_tab_win))

    vim.cmd("tabclose")
  end)

  it("registers quick peeks under the requesting window stack", function()
    local resolve
    peekstack.register_provider("test.async_origin_quick", function(_ctx, cb)
      resolve = cb
    end)

    peekstack.peek("test.async_origin_quick", { mode = "quick" })

    vim.api.nvim_set_current_win(win_b)
    resolve({ location_at(2) })

    assert.equals(1, vim.tbl_count(stack._ephemerals()))

    stack.close_ephemerals(win_b)
    assert.equals(1, vim.tbl_count(stack._ephemerals()))

    stack.close_ephemerals(win_a)
    assert.equals(0, vim.tbl_count(stack._ephemerals()))
  end)
end)
