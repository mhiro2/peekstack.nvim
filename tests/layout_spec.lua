local config = require("peekstack.config")
local layout = require("peekstack.core.layout")
local stack = require("peekstack.core.stack")
local helpers = require("tests.helpers")

describe("layout.compute", function()
  local original_columns
  local original_lines
  local original_cmdheight

  before_each(function()
    original_columns = vim.o.columns
    original_lines = vim.o.lines
    original_cmdheight = vim.o.cmdheight

    vim.o.columns = 120
    vim.o.lines = 40
    vim.o.cmdheight = 1
  end)

  after_each(function()
    vim.o.columns = original_columns
    vim.o.lines = original_lines
    vim.o.cmdheight = original_cmdheight
    config.setup({})
  end)

  it("shrinks and offsets for stack style", function()
    config.setup({
      ui = {
        layout = {
          style = "stack",
          offset = { row = 1, col = 2 },
          shrink = { w = 4, h = 2 },
          min_size = { w = 20, h = 10 },
          max_ratio = 1,
          zindex_base = 50,
        },
      },
    })
    local first = layout.compute(1)
    local second = layout.compute(2)

    assert.is_true(second.width < first.width)
    assert.is_true(second.height < first.height)
    assert.is_true(second.row >= first.row)
    assert.is_true(second.col >= first.col)
  end)

  it("cascades without shrinking for cascade style", function()
    config.setup({
      ui = {
        layout = {
          style = "cascade",
          offset = { row = 1, col = 2 },
          shrink = { w = 4, h = 2 },
          min_size = { w = 20, h = 10 },
          max_ratio = 1,
          zindex_base = 50,
        },
      },
    })
    local first = layout.compute(1)
    local second = layout.compute(2)

    assert.equals(first.width, second.width)
    assert.equals(first.height, second.height)
    assert.equals(first.row + 1, second.row)
    assert.equals(first.col + 2, second.col)
  end)

  it("keeps position and size for single style", function()
    config.setup({
      ui = {
        layout = {
          style = "single",
          offset = { row = 1, col = 2 },
          shrink = { w = 4, h = 2 },
          min_size = { w = 20, h = 10 },
          max_ratio = 1,
          zindex_base = 50,
        },
      },
    })
    local first = layout.compute(1)
    local second = layout.compute(2)

    assert.equals(first.width, second.width)
    assert.equals(first.height, second.height)
    assert.equals(first.row, second.row)
    assert.equals(first.col, second.col)
  end)
end)

describe("layout.update_focus_zindex", function()
  before_each(function()
    stack._reset()
    config.setup({})
  end)

  after_each(function()
    -- close all popups
    local s = stack.current_stack()
    for i = #s.popups, 1, -1 do
      stack.close(s.popups[i].id)
    end
    stack._reset()
  end)

  it("raises focused popup above all others", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    local m3 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)
    assert.is_not_nil(m3)

    local s = stack.current_stack()
    local base = config.get().ui.layout.zindex_base

    -- Before: focused popup (m3) is raised above natural order
    local cfg1 = vim.api.nvim_win_get_config(m1.winid)
    local cfg2 = vim.api.nvim_win_get_config(m2.winid)
    local cfg3 = vim.api.nvim_win_get_config(m3.winid)
    assert.equals(base, cfg1.zindex)
    assert.equals(base + 1, cfg2.zindex)
    assert.equals(base + 3, cfg3.zindex)

    -- Focus m1 (the bottom popup)
    layout.update_focus_zindex(s, m1.winid)

    -- After: m1 should be at the top (base + 3), others at natural
    cfg1 = vim.api.nvim_win_get_config(m1.winid)
    cfg2 = vim.api.nvim_win_get_config(m2.winid)
    cfg3 = vim.api.nvim_win_get_config(m3.winid)

    assert.equals(base + 3, cfg1.zindex) -- focused → top
    assert.equals(base + 1, cfg2.zindex) -- natural
    assert.equals(base + 2, cfg3.zindex) -- natural
  end)

  it("restores natural zindex when a different popup is focused", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    local s = stack.current_stack()
    local base = config.get().ui.layout.zindex_base

    -- Focus m1
    layout.update_focus_zindex(s, m1.winid)
    local cfg1 = vim.api.nvim_win_get_config(m1.winid)
    assert.equals(base + 2, cfg1.zindex)

    -- Now focus m2
    layout.update_focus_zindex(s, m2.winid)
    cfg1 = vim.api.nvim_win_get_config(m1.winid)
    local cfg2 = vim.api.nvim_win_get_config(m2.winid)

    assert.equals(base, cfg1.zindex) -- restored to natural
    assert.equals(base + 2, cfg2.zindex) -- now focused → top
  end)

  it("keeps focused popup above others after reflow", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    stack.focus_by_id(m1.id)
    stack.reflow_all()

    local base = config.get().ui.layout.zindex_base
    local cfg1 = vim.api.nvim_win_get_config(m1.winid)
    local cfg2 = vim.api.nvim_win_get_config(m2.winid)
    assert.equals(base + 2, cfg1.zindex)
    assert.equals(base + 1, cfg2.zindex)
  end)
end)
