describe("peekstack.ui.stack_view", function()
  local config = require("peekstack.config")
  local stack = require("peekstack.core.stack")
  local stack_view = require("peekstack.ui.stack_view")
  local helpers = require("tests.helpers")

  local function location_for(path)
    return {
      uri = vim.uri_from_fname(path),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }
  end

  before_each(function()
    config.setup({})
    stack._reset()
    stack_view._get_state().filter = nil
  end)

  after_each(function()
    local s = stack.current_stack()
    for i = #s.popups, 1, -1 do
      stack.close(s.popups[i].id)
    end
    if stack_view._get_state().winid then
      stack_view.toggle()
    end
    stack._reset()
  end)

  it("filters stack entries by query", function()
    local root_winid = vim.api.nvim_get_current_win()
    local s = stack.current_stack(root_winid)
    s.popups = {
      { id = 1, title = "Alpha", location = location_for("/tmp/alpha.lua"), pinned = false },
      { id = 2, title = "Beta", location = location_for("/tmp/beta.lua"), pinned = false },
    }

    stack_view.open()
    local state = stack_view._get_state()
    state.filter = "alp"
    stack_view._render(state)

    local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")

    assert.is_true(joined:find("Filter: alp", 1, true) ~= nil)
    assert.is_true(joined:find("Alpha", 1, true) ~= nil)
    assert.is_true(joined:find("Beta", 1, true) == nil)
  end)

  it("renders no matches when filter excludes all items", function()
    local root_winid = vim.api.nvim_get_current_win()
    local s = stack.current_stack(root_winid)
    s.popups = {
      { id = 1, title = "Alpha", location = location_for("/tmp/alpha.lua"), pinned = false },
    }

    stack_view.open()
    local state = stack_view._get_state()
    state.filter = "zzz"
    stack_view._render(state)

    local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")

    assert.is_true(joined:find("No matches", 1, true) ~= nil)
  end)

  it("renders header when filter is not set", function()
    local root_winid = vim.api.nvim_get_current_win()
    local s = stack.current_stack(root_winid)
    s.popups = {
      { id = 1, title = "Alpha", location = location_for("/tmp/alpha.lua"), pinned = false },
      { id = 2, title = "Beta", location = location_for("/tmp/beta.lua"), pinned = false },
    }

    stack_view.open()
    local state = stack_view._get_state()
    stack_view._render(state)

    local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
    assert.is_true(lines[1]:find("Stack: 2", 1, true) ~= nil)
  end)

  it("renders empty state with header", function()
    stack_view.open()
    local state = stack_view._get_state()
    stack_view._render(state)

    local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")

    assert.is_true(joined:find("Stack: 0", 1, true) ~= nil)
    assert.is_true(joined:find("No stack entries", 1, true) ~= nil)
  end)

  it("enables cursorline highlight in stack view", function()
    stack_view.open()
    local state = stack_view._get_state()

    assert.is_true(vim.wo[state.winid].cursorline)
    local winhighlight = vim.wo[state.winid].winhighlight or ""
    assert.is_true(winhighlight:find("CursorLine:PeekstackStackViewCursorLine", 1, true) ~= nil)
  end)

  it("renders pin badge for pinned items", function()
    local root_winid = vim.api.nvim_get_current_win()
    local s = stack.current_stack(root_winid)
    s.popups = {
      { id = 1, title = "Alpha", location = location_for("/tmp/alpha.lua"), pinned = true },
    }

    stack_view.open()
    local state = stack_view._get_state()
    stack_view._render(state)

    local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
    assert.is_true(lines[2]:find("• ", 1, true) ~= nil)
  end)

  it("has U keymap bound in stack view buffer", function()
    local root_winid = vim.api.nvim_get_current_win()
    local s = stack.current_stack(root_winid)
    s.popups = {
      { id = 1, title = "Alpha", location = location_for("/tmp/alpha.lua"), pinned = false },
    }

    stack_view.open()
    local state = stack_view._get_state()
    assert.is_not_nil(state.bufnr)

    local keymaps = vim.api.nvim_buf_get_keymap(state.bufnr, "n")
    local found = false
    for _, km in ipairs(keymaps) do
      if km.lhs == "U" then
        found = true
        break
      end
    end
    assert.is_true(found, "U keymap should be bound in stack view")
  end)

  it("has H keymap bound in stack view buffer", function()
    local root_winid = vim.api.nvim_get_current_win()
    local s = stack.current_stack(root_winid)
    s.popups = {
      { id = 1, title = "Alpha", location = location_for("/tmp/alpha.lua"), pinned = false },
    }

    stack_view.open()
    local state = stack_view._get_state()
    assert.is_not_nil(state.bufnr)

    local keymaps = vim.api.nvim_buf_get_keymap(state.bufnr, "n")
    local found = false
    for _, km in ipairs(keymaps) do
      if km.lhs == "H" then
        found = true
        break
      end
    end
    assert.is_true(found, "H keymap should be bound in stack view")
  end)

  it("does not error when render is called after close", function()
    stack_view.open()
    local state = stack_view._get_state()
    stack_view.toggle()

    assert.has_no.errors(function()
      stack_view._render(state)
    end)
  end)

  it("creates distinct autoclose groups per tab", function()
    local original_tab = vim.api.nvim_get_current_tabpage()

    stack_view.open()
    local state1 = stack_view._get_state()
    assert.is_not_nil(state1.autoclose_group)

    vim.api.nvim_cmd({ cmd = "tabnew" }, {})
    stack_view.open()
    local state2 = stack_view._get_state()
    assert.is_not_nil(state2.autoclose_group)

    assert.is_true(state1.autoclose_group ~= state2.autoclose_group)

    stack_view.toggle()
    vim.api.nvim_cmd({ cmd = "tabclose" }, {})
    vim.api.nvim_set_current_tabpage(original_tab)

    local state_back = stack_view._get_state()
    if state_back.winid then
      stack_view.toggle()
    end
  end)

  it("cleans up tab states on tab close", function()
    stack_view._get_state()
    local initial_count = stack_view._state_count()

    vim.api.nvim_cmd({ cmd = "tabnew" }, {})
    stack_view.open()
    local state = stack_view._get_state()
    vim.api.nvim_set_current_win(state.winid)

    vim.api.nvim_feedkeys("?", "nx", false)
    vim.wait(50, function()
      return state.help_winid ~= nil and vim.api.nvim_win_is_valid(state.help_winid)
    end)

    local help_winid = state.help_winid
    vim.api.nvim_cmd({ cmd = "tabclose" }, {})

    vim.wait(50, function()
      return stack_view._state_count() == initial_count
    end)

    if help_winid then
      assert.is_false(vim.api.nvim_win_is_valid(help_winid))
    end
  end)

  it("restores focus to stack view after undo close", function()
    local loc = helpers.make_location()
    local model = stack.push(loc)
    assert.is_not_nil(model)
    stack.close(model.id)

    stack_view.open()
    local state = stack_view._get_state()
    vim.api.nvim_set_current_win(state.winid)

    vim.api.nvim_feedkeys("u", "nx", false)
    vim.wait(50, function()
      return vim.api.nvim_get_current_win() == state.winid
    end)

    assert.equals(state.winid, vim.api.nvim_get_current_win())
  end)

  it("restores focus to stack view after history select", function()
    local loc = helpers.make_location()
    local model = stack.push(loc)
    assert.is_not_nil(model)
    stack.close(model.id)

    stack_view.open()
    local state = stack_view._get_state()
    vim.api.nvim_set_current_win(state.winid)

    local original_select = vim.ui.select
    local ok, err = pcall(function()
      vim.ui.select = function(items, _opts, on_choice)
        on_choice(items[1])
      end

      vim.api.nvim_feedkeys("H", "nx", false)
      vim.wait(50, function()
        return vim.api.nvim_get_current_win() == state.winid
      end)

      assert.equals(state.winid, vim.api.nvim_get_current_win())
    end)
    vim.ui.select = original_select
    if not ok then
      error(err)
    end
  end)

  it("truncates long titles in stack view", function()
    config.setup({ ui = { path = { max_width = 10 } } })
    stack_view.open()
    local state = stack_view._get_state()
    local s = stack.current_stack(state.root_winid)
    s.popups = {
      { id = 1, title = "a-very-very-long-title", location = location_for("/tmp/alpha.lua"), pinned = false },
    }
    stack_view._render(state)

    local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")

    assert.is_true(joined:find("...", 1, true) ~= nil)
  end)

  it("closes help when focus leaves the help window", function()
    stack_view.open()
    local state = stack_view._get_state()
    vim.api.nvim_set_current_win(state.winid)

    vim.api.nvim_feedkeys("?", "nx", false)
    vim.wait(50, function()
      return state.help_winid ~= nil and vim.api.nvim_win_is_valid(state.help_winid)
    end)

    vim.api.nvim_set_current_win(state.root_winid)
    vim.wait(50, function()
      return state.help_winid == nil or not vim.api.nvim_win_is_valid(state.help_winid)
    end)

    assert.is_nil(state.help_winid)
  end)

  it("shows focus marker on the focused popup", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    local m2 = stack.push(loc)
    assert.is_not_nil(m1)
    assert.is_not_nil(m2)

    stack_view.open()
    local state = stack_view._get_state()
    stack_view._render(state)

    local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)

    -- m2 is the focused one (last pushed), it should be the second visible entry
    -- Entry lines start after header (line 1)
    local has_focused = false
    local has_unfocused = false
    for _, line in ipairs(lines) do
      if line:find("▶", 1, true) then
        has_focused = true
      end
      if line:match("^  %d+%.") then
        has_unfocused = true
      end
    end

    assert.is_true(has_focused, "should have a focused marker")
    assert.is_true(has_unfocused, "should have an unfocused entry")
  end)

  it("does not show focus marker on unfocused popup", function()
    local loc = helpers.make_location()
    local m1 = stack.push(loc)
    assert.is_not_nil(m1)

    stack_view.open()
    local state = stack_view._get_state()
    stack_view._render(state)

    local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
    -- Only one popup and it is focused, so all entries have the marker
    local focused_count = 0
    for _, line in ipairs(lines) do
      if line:find("▶", 1, true) then
        focused_count = focused_count + 1
      end
    end
    assert.equals(1, focused_count)
  end)

  it("renders preview line with source code", function()
    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "local x = 42" }, tmpfile)

    local loc = helpers.make_location({
      uri = vim.uri_from_fname(tmpfile),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
    })
    local model = stack.push(loc)
    assert.is_not_nil(model)

    stack_view.open()
    local state = stack_view._get_state()
    stack_view._render(state)

    local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")

    assert.is_true(joined:find("local x = 42", 1, true) ~= nil, "preview line should contain source code")

    vim.fn.delete(tmpfile)
  end)

  it("does not crash when source buffer is invalid for preview", function()
    local root_winid = vim.api.nvim_get_current_win()
    local s = stack.current_stack(root_winid)
    s.popups = {
      {
        id = 1,
        title = "Alpha",
        location = location_for("/tmp/alpha.lua"),
        pinned = false,
        source_bufnr = -1,
        bufnr = -1,
      },
    }
    s.focused_id = 1

    stack_view.open()
    local state = stack_view._get_state()
    assert.has_no.errors(function()
      stack_view._render(state)
    end)
  end)

  it("maps preview line to the same popup id", function()
    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "local x = 42" }, tmpfile)

    local loc = helpers.make_location({
      uri = vim.uri_from_fname(tmpfile),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
    })
    local model = stack.push(loc)
    assert.is_not_nil(model)

    stack_view.open()
    local state = stack_view._get_state()
    stack_view._render(state)

    -- Find all line numbers mapped to this popup id
    local mapped_lines = {}
    for line_nr, id in pairs(state.line_to_id) do
      if id == model.id then
        table.insert(mapped_lines, line_nr)
      end
    end

    -- Should have at least 2 entries: the entry line and the preview line
    assert.is_true(#mapped_lines >= 2, "preview line should also map to the popup id")

    vim.fn.delete(tmpfile)
  end)
end)
