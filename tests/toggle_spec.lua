local stack = require("peekstack.core.stack")
local config = require("peekstack.config")
local events = require("peekstack.core.events")
local helpers = require("tests.helpers")

describe("stack.toggle", function()
  before_each(function()
    stack._reset()
    config.setup({})
    events.setup()
  end)

  after_each(function()
    local s = stack.current_stack()
    -- Restore visibility so windows can be closed normally
    if s.hidden then
      stack.toggle()
    end
    for i = #s.popups, 1, -1 do
      stack.close(s.popups[i].id)
    end
    stack._reset()
  end)

  it("returns false on empty stack", function()
    assert.is_false(stack.toggle())
    assert.is_false(stack.is_hidden())
  end)

  it("hides all popup windows", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    assert.is_true(stack.toggle())
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
    stack.toggle()
    assert.is_true(stack.is_hidden())

    -- Show
    assert.is_true(stack.toggle())
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

    stack.toggle()
    stack.toggle()

    local s = stack.current_stack()
    assert.equals(id1, s.popups[1].id)
    assert.equals(id2, s.popups[2].id)
  end)

  it("auto-shows when push is called while hidden", function()
    local loc = helpers.make_location()
    stack.push(loc)

    stack.toggle()
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

    stack.toggle()
    assert.is_true(stack.is_hidden())

    stack.close_all()
    assert.is_false(stack.is_hidden())

    local s = stack.current_stack()
    assert.equals(0, #s.popups)
  end)

  it("reflow_all skips hidden stack without error", function()
    local loc = helpers.make_location()
    stack.push(loc)
    stack.push(loc)

    stack.toggle()
    assert.is_true(stack.is_hidden())

    -- reflow_all should skip hidden popups (winid=nil) safely
    assert.has_no.errors(function()
      stack.reflow_all()
    end)

    -- Popups should still be in the stack
    local s = stack.current_stack()
    assert.equals(2, #s.popups)
    for _, item in ipairs(s.popups) do
      assert.is_nil(item.winid)
    end
  end)

  it("close by id works after hide/show cycle", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)

    -- Hide then show
    stack.toggle()
    stack.toggle()

    -- close should find the popup by its original id
    assert.is_true(stack.close(m2.id))
    assert.is_true(stack.close(m1.id))

    local s = stack.current_stack()
    assert.equals(0, #s.popups)
  end)

  it("keymaps reference correct popup id after hide/show cycle", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    local first_id, second_id = m1.id, m2.id
    local old_winids = { m1.winid, m2.winid }

    -- Hide then show (recreates windows, buffers and keymaps)
    stack.toggle()
    stack.toggle()

    local s = stack.current_stack()
    assert.equals(2, #s.popups)
    local first, second = s.popups[1], s.popups[2]
    assert.equals(first_id, first.id)
    assert.equals(second_id, second.id)
    for _, old in ipairs(old_winids) do
      assert.is_false(vim.api.nvim_win_is_valid(old))
    end
    assert.equals(first_id, vim.b[first.bufnr].peekstack_popup_id)

    -- Press the configured close key in the first (non-top) popup.
    vim.api.nvim_set_current_win(first.winid)
    local close_key = vim.api.nvim_replace_termcodes(config.get().ui.keys.close, true, false, true)
    vim.api.nvim_feedkeys(close_key, "x", false)

    assert.is_false(vim.api.nvim_win_is_valid(first.winid))
    assert.is_nil(stack.find_by_id(first_id))
    assert.is_true(vim.api.nvim_win_is_valid(second.winid))
    assert.equals(second, stack.find_by_id(second_id))
    assert.same({ second }, stack.list())
  end)

  it("does not leak popups to history when hiding", function()
    local loc = helpers.make_location()
    stack.push(loc)
    stack.push(loc)

    local history_before = #stack.history_list()
    stack.toggle()
    local history_after = #stack.history_list()

    assert.equals(history_before, history_after)
  end)
end)
