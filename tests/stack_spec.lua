local stack = require("peekstack.core.stack")
local config = require("peekstack.config")
local helpers = require("tests.helpers")

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

describe("stack.focus_relative", function()
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

  it("updates zindex when focus_prev changes focused popup", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    assert.equals(m2.winid, vim.api.nvim_get_current_win())
    assert.is_true(stack.focus_prev())
    assert.equals(m1.winid, vim.api.nvim_get_current_win())

    local base = config.get().ui.layout.zindex_base
    local cfg1 = vim.api.nvim_win_get_config(m1.winid)
    local cfg2 = vim.api.nvim_win_get_config(m2.winid)
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

  it("does not emit duplicate close events when root window closes", function()
    local popup = require("peekstack.core.popup")
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    local counts = {}
    local group = vim.api.nvim_create_augroup("PeekstackTestCloseEvents", { clear = true })
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "PeekstackClose",
      callback = function(args)
        local id = args.data and args.data.popup_id
        if id then
          counts[id] = (counts[id] or 0) + 1
        end
      end,
    })

    local root_winid = stack.current_stack().root_winid
    local original_close = popup.close
    local ok, err = pcall(function()
      popup.close = function(item)
        original_close(item)
        stack.handle_win_closed(item.winid)
      end
      stack.handle_win_closed(root_winid)
    end)
    popup.close = original_close
    pcall(vim.api.nvim_del_augroup_by_id, group)
    if not ok then
      error(err)
    end

    assert.equals(1, counts[m1.id])
    assert.equals(1, counts[m2.id])
  end)

  it("clears diagnostic extmarks when source-mode popup is closed manually", function()
    local location = helpers.make_location({
      provider = "diagnostics.under_cursor",
      text = "manual close leak check",
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
    })
    local model = stack.push(location, { buffer_mode = "source" })
    assert.is_not_nil(model)

    local ns = vim.api.nvim_get_namespaces().peekstack_diagnostics
    assert.is_not_nil(ns)
    local before = vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, {})
    assert.is_true(#before > 0)

    vim.api.nvim_win_close(model.winid, true)
    stack.handle_win_closed(model.winid)

    local after = vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, {})
    assert.equals(0, #after)
  end)
end)

describe("stack parent popup chain", function()
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

  it("sets parent_popup_id when pushing from a popup window", function()
    local loc = helpers.make_location()
    local parent = stack.push(loc)
    assert.is_not_nil(parent)

    vim.api.nvim_set_current_win(parent.winid)
    local child = stack.push(loc)
    assert.is_not_nil(child)

    assert.equals(parent.id, child.parent_popup_id)
  end)

  it("does not set parent_popup_id when pushing from a normal window", function()
    local root_winid = vim.api.nvim_get_current_win()
    local loc = helpers.make_location()
    local first = stack.push(loc)
    assert.is_not_nil(first)

    vim.api.nvim_set_current_win(root_winid)
    local second = stack.push(loc)
    assert.is_not_nil(second)

    assert.is_nil(second.parent_popup_id)
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

describe("stack lookup indexes", function()
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

  it("finds stack popups by id and winid", function()
    local loc = helpers.make_location()
    local model = stack.push(loc)
    assert.is_not_nil(model)

    local by_id = stack.find_by_id(model.id)
    assert.is_not_nil(by_id)
    assert.equals(model.id, by_id.id)

    local owner, by_winid = stack.find_by_winid(model.winid)
    assert.is_not_nil(owner)
    assert.is_not_nil(by_winid)
    assert.equals(model.id, by_winid.id)
  end)

  it("returns ephemeral popups for winid lookup", function()
    local loc = helpers.make_location()
    local ephemeral = stack.push(loc, { stack = false })
    assert.is_not_nil(ephemeral)

    local owner, by_winid = stack.find_by_winid(ephemeral.winid)
    assert.is_nil(owner)
    assert.is_not_nil(by_winid)
    assert.equals(ephemeral.id, by_winid.id)
  end)

  it("clears id and winid lookups when a popup is closed", function()
    local loc = helpers.make_location()
    local model = stack.push(loc)
    assert.is_not_nil(model)
    local winid = model.winid
    local id = model.id

    assert.is_true(stack.close(id))
    assert.is_nil(stack.find_by_id(id))

    local owner, by_winid = stack.find_by_winid(winid)
    assert.is_nil(owner)
    assert.is_nil(by_winid)
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

  it("keeps parent_popup_id when reopening a child popup", function()
    local loc = helpers.make_location()
    local parent = stack.push(loc)
    assert.is_not_nil(parent)

    vim.api.nvim_set_current_win(parent.winid)
    local child = stack.push(loc)
    assert.is_not_nil(child)
    assert.equals(parent.id, child.parent_popup_id)

    child.winid = -1
    local reopened = stack.reopen_by_id(child.id)
    assert.is_not_nil(reopened)
    assert.equals(parent.id, reopened.parent_popup_id)

    stack.close(child.id)
  end)
end)

describe("stack.focused_id", function()
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

  it("is set to the pushed popup id after push", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.equals(m1.id, stack.focused_id())

    local m2 = stack.push(loc)
    assert.is_not_nil(m2)
    assert.equals(m2.id, stack.focused_id())
  end)

  it("is updated after focus_by_id", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    assert.equals(m2.id, stack.focused_id())

    stack.focus_by_id(m1.id)
    assert.equals(m1.id, stack.focused_id())
  end)

  it("is updated to next popup when focused popup is closed", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    assert.equals(m2.id, stack.focused_id())
    stack.close(m2.id)
    assert.equals(m1.id, stack.focused_id())
  end)

  it("is nil when last popup is closed", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    assert.is_not_nil(m1)

    stack.close(m1.id)
    assert.is_nil(stack.focused_id())
  end)

  it("is updated to restored popup after restore_last", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    assert.is_not_nil(m1)

    stack.close(m1.id)
    assert.is_nil(stack.focused_id())

    local restored = stack.restore_last()
    assert.is_not_nil(restored)
    assert.equals(restored.id, stack.focused_id())

    stack.close(restored.id)
  end)

  it("is nil after close_all", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    assert.equals(m2.id, stack.focused_id())
    stack.close_all()
    assert.is_nil(stack.focused_id())
  end)

  it("is updated when focused popup window is closed externally", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    assert.equals(m2.id, stack.focused_id())

    -- Simulate external window close
    vim.api.nvim_win_close(m2.winid, true)
    stack.handle_win_closed(m2.winid)

    assert.equals(m1.id, stack.focused_id())
  end)
end)
