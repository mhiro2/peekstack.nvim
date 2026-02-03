local stack = require("peekstack.core.stack")
local config = require("peekstack.config")
local helpers = require("tests.helpers")

describe("stack.move_by_id", function()
  before_each(function()
    stack._reset()
  end)

  it("moves items within the stack", function()
    local s = stack.current_stack()
    s.popups = {
      { id = 1 },
      { id = 2 },
      { id = 3 },
    }

    assert.is_true(stack.move_by_id(1, 1))
    assert.equals(2, s.popups[1].id)
    assert.equals(1, s.popups[2].id)
    assert.equals(3, s.popups[3].id)

    assert.is_true(stack.move_by_id(3, -1))
    assert.equals(2, s.popups[1].id)
    assert.equals(3, s.popups[2].id)
    assert.equals(1, s.popups[3].id)
  end)

  it("returns false when movement is not possible", function()
    local s = stack.current_stack()
    s.popups = {
      { id = 1 },
      { id = 2 },
    }

    assert.is_false(stack.move_by_id(1, -1))
    assert.is_false(stack.move_by_id(2, 1))
    assert.is_false(stack.move_by_id(99, 1))
  end)
end)

describe("stack.focus_by_id", function()
  before_each(function()
    stack._reset()
    config.setup({})
  end)

  after_each(function()
    local s = stack.current_stack()
    for i = #s.popups, 1, -1 do
      stack.close(s.popups[i].id)
    end
    stack._reset()
  end)

  it("raises focused popup zindex", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    local base = config.get().ui.layout.zindex_base
    local cfg1 = vim.api.nvim_win_get_config(m1.winid)
    local cfg2 = vim.api.nvim_win_get_config(m2.winid)
    assert.equals(base, cfg1.zindex)
    assert.equals(base + 2, cfg2.zindex)

    stack.focus_by_id(m1.id)

    cfg1 = vim.api.nvim_win_get_config(m1.winid)
    cfg2 = vim.api.nvim_win_get_config(m2.winid)
    assert.equals(base + 2, cfg1.zindex)
    assert.equals(base + 1, cfg2.zindex)
  end)
end)

describe("stack.handle_win_closed", function()
  before_each(function()
    stack._reset()
    config.setup({})
  end)

  after_each(function()
    local s = stack.current_stack()
    for i = #s.popups, 1, -1 do
      stack.close(s.popups[i].id)
    end
    stack._reset()
  end)

  it("keeps focus zindex when unrelated window closes", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    stack.focus_by_id(m1.id)

    local base = config.get().ui.layout.zindex_base
    local cfg1 = vim.api.nvim_win_get_config(m1.winid)
    local cfg2 = vim.api.nvim_win_get_config(m2.winid)
    assert.equals(base + 2, cfg1.zindex)
    assert.equals(base + 1, cfg2.zindex)

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 0,
      col = 0,
      width = 1,
      height = 1,
      style = "minimal",
    })
    vim.api.nvim_win_close(win, true)

    stack.handle_win_closed(win)

    cfg1 = vim.api.nvim_win_get_config(m1.winid)
    cfg2 = vim.api.nvim_win_get_config(m2.winid)
    assert.equals(base + 2, cfg1.zindex)
    assert.equals(base + 1, cfg2.zindex)
  end)
end)

describe("stack.close focus restore", function()
  before_each(function()
    stack._reset()
    config.setup({})
  end)

  after_each(function()
    local s = stack.current_stack()
    for i = #s.popups, 1, -1 do
      stack.close(s.popups[i].id)
    end
    stack._reset()
  end)

  it("restores focus to the remaining popup when closing the current popup", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    assert.equals(m2.winid, vim.api.nvim_get_current_win())
    stack.close(m2.id)

    assert.equals(m1.winid, vim.api.nvim_get_current_win())
  end)

  it("does not restore focus when closing from a non-popup window", function()
    local root_winid = vim.api.nvim_get_current_win()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    vim.api.nvim_set_current_win(root_winid)
    stack.close(m2.id)

    assert.equals(root_winid, vim.api.nvim_get_current_win())
  end)
end)

describe("stack.handle_origin_wipeout", function()
  before_each(function()
    stack._reset()
    config.setup({})
  end)

  after_each(function()
    stack._reset()
  end)

  it("keeps popups whose origin is another popup", function()
    local s = stack.current_stack()
    s.popups = {
      {
        id = 1,
        origin = { bufnr = 10 },
        origin_is_popup = true,
      },
      {
        id = 2,
        origin = { bufnr = 10 },
        origin_is_popup = false,
      },
    }

    stack.handle_origin_wipeout(10)

    assert.equals(1, #s.popups)
    assert.equals(1, s.popups[1].id)
  end)
end)

describe("stack.close_by_id", function()
  before_each(function()
    stack._reset()
    config.setup({})
  end)

  after_each(function()
    local s = stack.current_stack()
    for i = #s.popups, 1, -1 do
      stack.close(s.popups[i].id)
    end
    stack._reset()
  end)

  it("closes only by id even if winid matches another popup", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    local collide_id = m2.winid
    m1.id = collide_id

    assert.is_true(stack.close_by_id(collide_id))
    local s = stack.current_stack()
    assert.equals(1, #s.popups)
    assert.equals(m2.winid, s.popups[1].winid)
  end)
end)

describe("stack history", function()
  before_each(function()
    stack._reset()
    config.setup({})
  end)

  after_each(function()
    stack._reset()
  end)

  it("saves buffer_mode and source_bufnr in history on close", function()
    local loc = helpers.make_location()
    local model = stack.push(loc)
    assert.is_not_nil(model)

    local popup_id = model.id
    stack.close(popup_id)

    local history = stack.history_list()
    assert.equals(1, #history)
    assert.equals("copy", history[1].buffer_mode)
    assert.is_not_nil(history[1].source_bufnr)
    assert.is_not_nil(history[1].closed_at)
    assert.is_not_nil(history[1].created_at)
  end)

  it("saves buffer_mode as source for source mode popups", function()
    local loc = helpers.make_location()
    local model = stack.push(loc, { buffer_mode = "source" })
    assert.is_not_nil(model)

    stack.close(model.id)

    local history = stack.history_list()
    assert.equals(1, #history)
    assert.equals("source", history[1].buffer_mode)
  end)

  it("saves restore_index in history", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    -- Close the first popup (index 1)
    stack.close(m1.id)

    local history = stack.history_list()
    assert.equals(1, #history)
    assert.equals(1, history[1].restore_index)
  end)

  it("restore_last passes buffer_mode to recreated popup", function()
    local loc = helpers.make_location()
    local model = stack.push(loc, { buffer_mode = "source" })
    assert.is_not_nil(model)

    stack.close(model.id)
    local restored = stack.restore_last()
    assert.is_not_nil(restored)
    assert.equals("source", restored.buffer_mode)
    stack.close(restored.id)
  end)

  it("restore_all restores all history entries", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    stack.close(m1.id)
    stack.close(m2.id)

    assert.equals(2, #stack.history_list())

    local restored = stack.restore_all()
    assert.equals(2, #restored)
    assert.equals(0, #stack.history_list())

    -- Cleanup
    for _, r in ipairs(restored) do
      stack.close(r.id)
    end
  end)

  it("keeps history entry when restore_last fails", function()
    local s = stack.current_stack()
    s.history = {
      {
        location = { uri = nil },
        title = "broken",
        buffer_mode = "copy",
      },
    }

    local restored = stack.restore_last()
    assert.is_nil(restored)
    assert.equals(1, #stack.history_list())
  end)

  it("keeps failed entries when restore_all restores partially", function()
    local loc = helpers.make_location()
    local model = stack.push(loc)
    assert.is_not_nil(model)
    stack.close(model.id)

    local history = stack.history_list()
    table.insert(history, {
      location = { uri = nil },
      title = "broken",
      buffer_mode = "copy",
    })

    local restored = stack.restore_all()
    assert.equals(1, #restored)
    assert.equals(1, #stack.history_list())

    for _, r in ipairs(restored) do
      stack.close(r.id)
    end
  end)

  it("history_list returns history entries", function()
    local loc = helpers.make_location()
    local model = stack.push(loc)
    assert.is_not_nil(model)

    stack.close(model.id)

    local history = stack.history_list()
    assert.equals(1, #history)
    assert.is_not_nil(history[1].location)
  end)

  it("clear_history empties the history", function()
    local loc = helpers.make_location()
    local model = stack.push(loc)
    assert.is_not_nil(model)

    stack.close(model.id)
    assert.equals(1, #stack.history_list())

    stack.clear_history()
    assert.equals(0, #stack.history_list())
  end)

  it("respects history max_items from config", function()
    config.setup({ ui = { popup = { history = { max_items = 2 } } } })

    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    stack.close(m1.id)
    local m2 = stack.push(loc)
    stack.close(m2.id)
    local m3 = stack.push(loc)
    stack.close(m3.id)

    local history = stack.history_list()
    assert.equals(2, #history)
  end)
end)

describe("stack focus reopen", function()
  before_each(function()
    stack._reset()
    config.setup({})
  end)

  after_each(function()
    stack._reset()
  end)

  it("reopens popup when focus_by_id target window is invalid", function()
    local loc = helpers.make_location()
    local model = stack.push(loc)
    assert.is_not_nil(model)
    local old_winid = model.winid

    model.winid = -1
    local ok = stack.focus_by_id(model.id)
    assert.is_true(ok)

    stack.close(model.id)
    if vim.api.nvim_win_is_valid(old_winid) then
      vim.api.nvim_win_close(old_winid, true)
    end
  end)
end)
