local stack = require("peekstack.core.stack")
local config = require("peekstack.config")
local events = require("peekstack.core.events")
local helpers = require("tests.helpers")

describe("stack.toggle_visibility", function()
  before_each(function()
    stack._reset()
    config.setup({})
    events.setup()
  end)

  after_each(function()
    local s = stack.current_stack()
    -- Restore visibility so windows can be closed normally
    if s.hidden then
      stack.toggle_visibility()
    end
    for i = #s.popups, 1, -1 do
      stack.close(s.popups[i].id)
    end
    stack._reset()
  end)

  it("returns false on empty stack", function()
    assert.is_false(stack.toggle_visibility())
    assert.is_false(stack.is_hidden())
  end)

  it("hides all popup windows", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    assert.is_true(stack.toggle_visibility())
    assert.is_true(stack.is_hidden())

    -- Windows should be gone but popups remain in the stack
    local s = stack.current_stack()
    assert.equals(2, #s.popups)
    for _, item in ipairs(s.popups) do
      assert.is_nil(item.winid)
    end
  end)

  it("restores popup windows on second toggle", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    -- Hide
    stack.toggle_visibility()
    assert.is_true(stack.is_hidden())

    -- Show
    assert.is_true(stack.toggle_visibility())
    assert.is_false(stack.is_hidden())

    local s = stack.current_stack()
    assert.equals(2, #s.popups)
    for _, item in ipairs(s.popups) do
      assert.is_not_nil(item.winid)
      assert.is_true(vim.api.nvim_win_is_valid(item.winid))
    end
  end)

  it("preserves popup ids across hide/show cycle", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)

    local id1 = m1.id
    local id2 = m2.id

    stack.toggle_visibility()
    stack.toggle_visibility()

    local s = stack.current_stack()
    assert.equals(id1, s.popups[1].id)
    assert.equals(id2, s.popups[2].id)
  end)

  it("auto-shows when push is called while hidden", function()
    local loc = helpers.make_location()
    stack.push(loc)

    stack.toggle_visibility()
    assert.is_true(stack.is_hidden())

    -- Pushing should auto-show
    local m2 = stack.push(loc)
    assert.is_not_nil(m2)
    assert.is_false(stack.is_hidden())

    local s = stack.current_stack()
    assert.equals(2, #s.popups)
    for _, item in ipairs(s.popups) do
      assert.is_not_nil(item.winid)
      assert.is_true(vim.api.nvim_win_is_valid(item.winid))
    end
  end)

  it("close_all works while hidden", function()
    local loc = helpers.make_location()
    stack.push(loc)
    stack.push(loc)

    stack.toggle_visibility()
    assert.is_true(stack.is_hidden())

    stack.close_all()
    assert.is_false(stack.is_hidden())

    local s = stack.current_stack()
    assert.equals(0, #s.popups)
  end)

  it("does not leak popups to history when hiding", function()
    local loc = helpers.make_location()
    stack.push(loc)
    stack.push(loc)

    local history_before = #stack.history_list()
    stack.toggle_visibility()
    local history_after = #stack.history_list()

    assert.equals(history_before, history_after)
  end)
end)
