local stack = require("peekstack.core.stack")
local history = require("peekstack.core.history")
local config = require("peekstack.config")
local helpers = require("tests.helpers")

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

    local hist = stack.history_list()
    assert.equals(1, #hist)
    assert.equals("copy", hist[1].buffer_mode)
    assert.is_not_nil(hist[1].source_bufnr)
    assert.is_not_nil(hist[1].closed_at)
    assert.is_not_nil(hist[1].created_at)
  end)

  it("saves buffer_mode as source for source mode popups", function()
    local loc = helpers.make_location()
    local model = stack.push(loc, { buffer_mode = "source" })
    assert.is_not_nil(model)

    stack.close(model.id)

    local hist = stack.history_list()
    assert.equals(1, #hist)
    assert.equals("source", hist[1].buffer_mode)
  end)

  it("saves parent_popup_id for chained popups", function()
    local loc = helpers.make_location()
    local parent = stack.push(loc)
    assert.is_not_nil(parent)
    vim.api.nvim_set_current_win(parent.winid)

    local child = stack.push(loc)
    assert.is_not_nil(child)
    assert.equals(parent.id, child.parent_popup_id)

    stack.close(child.id)

    local hist = stack.history_list()
    assert.equals(1, #hist)
    assert.equals(parent.id, hist[1].parent_popup_id)
  end)

  it("saves restore_index in history", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    -- Close the first popup (index 1)
    stack.close(m1.id)

    local hist = stack.history_list()
    assert.equals(1, #hist)
    assert.equals(1, hist[1].restore_index)
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

  it("restore_last preserves parent_popup_id when parent still exists", function()
    local loc = helpers.make_location()
    local parent = stack.push(loc)
    assert.is_not_nil(parent)
    vim.api.nvim_set_current_win(parent.winid)

    local child = stack.push(loc)
    assert.is_not_nil(child)
    assert.equals(parent.id, child.parent_popup_id)

    stack.close(child.id)
    local restored = stack.restore_last()
    assert.is_not_nil(restored)
    assert.equals(parent.id, restored.parent_popup_id)

    stack.close(restored.id)
    stack.close(parent.id)
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

    local hist = stack.history_list()
    table.insert(hist, {
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

    local hist = stack.history_list()
    assert.equals(1, #hist)
    assert.is_not_nil(hist[1].location)
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

  it("saves popup_id in history on close", function()
    local loc = helpers.make_location()
    local model = stack.push(loc)
    assert.is_not_nil(model)
    local original_id = model.id

    stack.close(model.id)

    local hist = stack.history_list()
    assert.equals(1, #hist)
    assert.equals(original_id, hist[1].popup_id)
  end)

  it("restore_all remaps parent_popup_id for parent-child popups", function()
    local loc = helpers.make_location()
    local parent = stack.push(loc)
    assert.is_not_nil(parent)
    vim.api.nvim_set_current_win(parent.winid)

    local child = stack.push(loc)
    assert.is_not_nil(child)
    assert.equals(parent.id, child.parent_popup_id)

    local parent_original_id = parent.id

    -- Close child first, then parent (history stores newest last)
    stack.close(child.id)
    stack.close(parent.id)
    assert.equals(2, #stack.history_list())

    -- Restore all: parent is restored first (from end of history),
    -- then child. Child's parent_popup_id should be remapped to the
    -- new parent ID.
    local restored = stack.restore_all()
    assert.equals(2, #restored)

    -- Find the restored child (the one with a parent_popup_id)
    local restored_child = nil
    local restored_parent = nil
    for _, r in ipairs(restored) do
      if r.parent_popup_id then
        restored_child = r
      else
        restored_parent = r
      end
    end

    assert.is_not_nil(restored_parent)
    assert.is_not_nil(restored_child)
    -- The parent_popup_id should point to the NEW parent id, not the old one
    assert.equals(restored_parent.id, restored_child.parent_popup_id)
    assert.is_not.equals(parent_original_id, restored_parent.id)

    -- Cleanup
    for _, r in ipairs(restored) do
      stack.close(r.id)
    end
  end)

  it("restore_last remaps parent_popup_id to new parent id", function()
    local loc = helpers.make_location()
    local parent = stack.push(loc)
    assert.is_not_nil(parent)
    vim.api.nvim_set_current_win(parent.winid)

    local child = stack.push(loc)
    assert.is_not_nil(child)
    local original_parent_id = parent.id

    -- Close both: child first, then parent
    stack.close(child.id)
    stack.close(parent.id)
    assert.equals(2, #stack.history_list())

    -- Restore parent first (last closed = last in history)
    local restored_parent = stack.restore_last()
    assert.is_not_nil(restored_parent)
    assert.is_not.equals(original_parent_id, restored_parent.id)

    -- Restore child: its parent_popup_id should point to the NEW parent id
    local restored_child = stack.restore_last()
    assert.is_not_nil(restored_child)
    assert.equals(restored_parent.id, restored_child.parent_popup_id)

    -- Cleanup
    stack.close(restored_child.id)
    stack.close(restored_parent.id)
  end)

  it("restore_last drops orphaned parent_popup_id", function()
    local loc = helpers.make_location()
    local parent = stack.push(loc)
    assert.is_not_nil(parent)
    vim.api.nvim_set_current_win(parent.winid)

    local child = stack.push(loc)
    assert.is_not_nil(child)

    -- Close both
    stack.close(child.id)
    stack.close(parent.id)

    -- Only restore child (skip parent). Parent is gone so
    -- child's parent_popup_id should be nil.
    -- History is LIFO: parent is last, so remove it first without restoring
    table.remove(stack.history_list())

    local restored = stack.restore_last()
    assert.is_not_nil(restored)
    assert.is_nil(restored.parent_popup_id)

    stack.close(restored.id)
  end)

  it("restore_from_history remaps parent_popup_id using id_remap", function()
    local loc = helpers.make_location()
    local parent = stack.push(loc)
    assert.is_not_nil(parent)
    vim.api.nvim_set_current_win(parent.winid)

    local child = stack.push(loc)
    assert.is_not_nil(child)

    -- Close child only
    stack.close(child.id)
    assert.equals(1, #stack.history_list())

    -- Parent still exists, so parent_popup_id should remain valid
    local restored = stack.restore_from_history(1)
    assert.is_not_nil(restored)
    assert.equals(parent.id, restored.parent_popup_id)

    -- Cleanup
    stack.close(restored.id)
    stack.close(parent.id)
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

    local hist = stack.history_list()
    assert.equals(2, #hist)
  end)
end)

describe("history.build_entry", function()
  it("builds entry from popup model", function()
    local item = {
      id = 7,
      location = {
        uri = "file:///test.lua",
        range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
        provider = "test",
      },
      title = "test title",
      title_chunks = { { "test", "HL" } },
      pinned = true,
      buffer_mode = "source",
      source_bufnr = 42,
      created_at = 1000,
      parent_popup_id = 99,
    }

    local entry = history.build_entry(item, 3)

    assert.equals(7, entry.popup_id)
    assert.same(item.location, entry.location)
    assert.equals("test title", entry.title)
    assert.same({ { "test", "HL" } }, entry.title_chunks)
    assert.is_true(entry.pinned)
    assert.equals("source", entry.buffer_mode)
    assert.equals(42, entry.source_bufnr)
    assert.equals(1000, entry.created_at)
    assert.equals(3, entry.restore_index)
    assert.equals(99, entry.parent_popup_id)
    assert.is_not_nil(entry.closed_at)
  end)

  it("defaults buffer_mode to copy when nil", function()
    local item = {
      location = { uri = "file:///test.lua" },
      buffer_mode = nil,
    }

    local entry = history.build_entry(item, 1)
    assert.equals("copy", entry.buffer_mode)
  end)
end)

describe("history.push_entry", function()
  before_each(function()
    config.setup({})
  end)

  it("appends entry to stack history", function()
    local s = { history = {} }
    local entry = { location = {}, title = "a" }

    history.push_entry(s, entry)

    assert.equals(1, #s.history)
    assert.equals("a", s.history[1].title)
  end)

  it("enforces max_items limit", function()
    config.setup({ ui = { popup = { history = { max_items = 2 } } } })
    local s = { history = {} }

    history.push_entry(s, { location = {}, title = "a" })
    history.push_entry(s, { location = {}, title = "b" })
    history.push_entry(s, { location = {}, title = "c" })

    assert.equals(2, #s.history)
    assert.equals("b", s.history[1].title)
    assert.equals("c", s.history[2].title)
  end)
end)
