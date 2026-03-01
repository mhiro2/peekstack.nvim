local stack = require("peekstack.core.stack")
local config = require("peekstack.config")
local events = require("peekstack.core.events")
local helpers = require("tests.helpers")

describe("stack.toggle_zoom", function()
  before_each(function()
    stack._reset()
    config.setup({})
    events.setup()
  end)

  after_each(function()
    local s = stack.current_stack()
    if s.hidden then
      stack.toggle()
    end
    for i = #s.popups, 1, -1 do
      stack.close(s.popups[i].id)
    end
    stack._reset()
  end)

  it("returns false on empty stack", function()
    assert.is_false(stack.toggle_zoom())
    assert.is_false(stack.is_zoomed())
  end)

  it("zooms the top popup to fullscreen", function()
    local loc = helpers.make_location()
    stack.push(loc)
    local m2 = stack.push(loc)

    assert.is_true(stack.toggle_zoom())
    assert.is_true(stack.is_zoomed())

    local cfg = vim.api.nvim_win_get_config(m2.winid)
    local expected_w = vim.o.columns
    local expected_h = vim.o.lines - vim.o.cmdheight

    -- The zoomed popup should be at least close to fullscreen.
    -- nvim_win_set_config may adjust for border, so allow tolerance.
    assert.is_true(cfg.width >= expected_w - 2)
    assert.is_true(cfg.height >= expected_h - 2)
  end)

  it("unzooms on second toggle", function()
    local loc = helpers.make_location()
    stack.push(loc)
    local m2 = stack.push(loc)

    stack.toggle_zoom()
    assert.is_true(stack.is_zoomed())

    stack.toggle_zoom()
    assert.is_false(stack.is_zoomed())

    -- After unzoom, size should match normal layout
    local layout = require("peekstack.core.layout")
    local expected = layout.compute(2)
    local cfg = vim.api.nvim_win_get_config(m2.winid)
    assert.equals(expected.width, cfg.width)
    assert.equals(expected.height, cfg.height)
  end)

  it("clears zoom when the zoomed popup is closed", function()
    local loc = helpers.make_location()
    stack.push(loc)
    local m2 = stack.push(loc)

    stack.toggle_zoom()
    assert.is_true(stack.is_zoomed())

    stack.close(m2.id)
    assert.is_false(stack.is_zoomed())
  end)

  it("clears zoom on push", function()
    local loc = helpers.make_location()
    stack.push(loc)

    stack.toggle_zoom()
    assert.is_true(stack.is_zoomed())

    stack.push(loc)
    assert.is_false(stack.is_zoomed())
  end)

  it("clears zoom when hiding via toggle visibility", function()
    local loc = helpers.make_location()
    stack.push(loc)

    stack.toggle_zoom()
    assert.is_true(stack.is_zoomed())

    stack.toggle() -- hide
    assert.is_true(stack.is_hidden())
    assert.is_false(stack.is_zoomed())
  end)

  it("returns false when stack is hidden", function()
    local loc = helpers.make_location()
    stack.push(loc)

    stack.toggle() -- hide
    assert.is_false(stack.toggle_zoom())
    assert.is_false(stack.is_zoomed())
  end)

  it("clears zoom on close_all", function()
    local loc = helpers.make_location()
    stack.push(loc)
    stack.push(loc)

    stack.toggle_zoom()
    assert.is_true(stack.is_zoomed())

    stack.close_all()
    assert.is_false(stack.is_zoomed())
  end)

  it("sets zoomed border highlight", function()
    local loc = helpers.make_location()
    stack.push(loc)
    local m = stack.push(loc)

    stack.toggle_zoom()

    local whl = vim.wo[m.winid].winhighlight
    assert.truthy(whl:find("PeekstackPopupBorderZoomed"))
  end)

  it("restores normal border highlight on unzoom", function()
    local loc = helpers.make_location()
    stack.push(loc)
    local m = stack.push(loc)

    stack.toggle_zoom()
    stack.toggle_zoom()

    local whl = vim.wo[m.winid].winhighlight
    assert.falsy(whl:find("PeekstackPopupBorderZoomed"))
  end)

  it("zoomed zindex is above all popups regardless of zindex_base", function()
    config.setup({ ui = { layout = { zindex_base = 300 } } })
    events.setup()
    local loc = helpers.make_location()
    stack.push(loc)
    local m2 = stack.push(loc)

    stack.toggle_zoom()

    local s = stack.current_stack()
    local zoomed_cfg = vim.api.nvim_win_get_config(m2.winid)
    -- Zoomed zindex must be higher than any non-zoomed popup
    for _, p in ipairs(s.popups) do
      if p.id ~= m2.id and p.winid and vim.api.nvim_win_is_valid(p.winid) then
        local other_cfg = vim.api.nvim_win_get_config(p.winid)
        assert.is_true(zoomed_cfg.zindex > other_cfg.zindex)
      end
    end
  end)

  it("clears zoom when popup window is closed externally", function()
    local loc = helpers.make_location()
    stack.push(loc)
    local m2 = stack.push(loc)

    stack.toggle_zoom()
    assert.is_true(stack.is_zoomed())

    -- Simulate external close (e.g., nvim_win_close)
    vim.api.nvim_win_close(m2.winid, true)
    assert.is_false(stack.is_zoomed())
  end)
end)
