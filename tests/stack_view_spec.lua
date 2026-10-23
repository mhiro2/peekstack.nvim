describe("peekstack.ui.stack_view", function()
  local config = require("peekstack.config")
  local stack = require("peekstack.core.stack")
  local stack_view = require("peekstack.ui.stack_view")
  local state = require("peekstack.ui.stack_view.state")
  local helpers = require("tests.helpers")

  local initial_tabpage = nil

  local function location_for(path)
    return {
      uri = vim.uri_from_fname(path),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }
  end

  local function stack_view_context(tabpage)
    local wins = vim.api.nvim_tabpage_list_wins(tabpage or 0)
    for _, winid in ipairs(wins) do
      local bufnr = vim.api.nvim_win_get_buf(winid)
      if vim.bo[bufnr].filetype == "peekstack-stack" then
        return {
          winid = winid,
          bufnr = bufnr,
          root_winid = vim.api.nvim_win_get_var(winid, "peekstack_root_winid"),
        }
      end
    end
  end

  local function help_context(tabpage)
    local wins = vim.api.nvim_tabpage_list_wins(tabpage or 0)
    for _, winid in ipairs(wins) do
      local bufnr = vim.api.nvim_win_get_buf(winid)
      if vim.bo[bufnr].filetype == "peekstack-stack-help" then
        return {
          winid = winid,
          bufnr = bufnr,
        }
      end
    end
  end

  local function close_floating_windows()
    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
      if vim.api.nvim_tabpage_is_valid(tabpage) then
        for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
          local cfg = vim.api.nvim_win_get_config(winid)
          if cfg.relative ~= "" then
            pcall(vim.api.nvim_win_close, winid, true)
          end
        end
      end
    end
  end

  local function close_extra_tabs()
    local tabs = vim.api.nvim_list_tabpages()
    for idx = #tabs, 1, -1 do
      local tabpage = tabs[idx]
      if tabpage ~= initial_tabpage and vim.api.nvim_tabpage_is_valid(tabpage) then
        vim.api.nvim_set_current_tabpage(tabpage)
        vim.api.nvim_cmd({ cmd = "tabclose" }, {})
      end
    end
    if initial_tabpage and vim.api.nvim_tabpage_is_valid(initial_tabpage) then
      vim.api.nvim_set_current_tabpage(initial_tabpage)
    end
  end

  local function reset_stack_view_state()
    for _, s in pairs(state.all()) do
      state.cleanup(s)
      state.reset_open_state(s)
      s.filter = nil
    end
  end

  local function set_stack_items(items)
    local current = stack.current_stack(vim.api.nvim_get_current_win())
    current.popups = items
    current.focused_id = items[#items] and items[#items].id or nil
  end

  before_each(function()
    initial_tabpage = vim.api.nvim_get_current_tabpage()
    config.setup({})
    stack._reset()
    reset_stack_view_state()
  end)

  after_each(function()
    close_floating_windows()
    close_extra_tabs()
    stack._reset()
    reset_stack_view_state()
  end)

  it("resize_all updates open stack view dimensions", function()
    local original_columns = vim.o.columns

    local ok, err = pcall(function()
      -- Both widths stay above the 30 column minimum: 30% of 200 and 300.
      vim.o.columns = 200
      stack_view.open()
      local context = stack_view_context()
      assert.is_not_nil(context)
      local cfg_before = vim.api.nvim_win_get_config(context.winid)
      assert.equals(60, cfg_before.width)
      assert.equals(140, cfg_before.col)

      vim.o.columns = 300
      stack_view.resize_all()

      local cfg_after = vim.api.nvim_win_get_config(context.winid)
      assert.equals(90, cfg_after.width)
      assert.equals(210, cfg_after.col)
    end)

    vim.o.columns = original_columns
    if not ok then
      error(err)
    end
  end)

  it("resize_all does not error when stack view is closed", function()
    assert.has_no.errors(function()
      stack_view.resize_all()
    end)
  end)

  it("refresh_all does not error when stack view is closed", function()
    stack_view.open()
    local context = stack_view_context()
    assert.is_not_nil(context)

    vim.api.nvim_set_current_win(context.winid)
    stack_view.toggle()

    assert.has_no.errors(function()
      stack_view.refresh_all()
    end)
  end)

  it("enables cursorline highlight in stack view", function()
    stack_view.open()
    local context = stack_view_context()
    assert.is_not_nil(context)

    assert.is_true(vim.wo[context.winid].cursorline)
    local winhighlight = vim.wo[context.winid].winhighlight or ""
    assert.is_true(winhighlight:find("CursorLine:PeekstackStackViewCursorLine", 1, true) ~= nil)
  end)

  it("opens stack view on the left when configured", function()
    config.setup({
      ui = {
        stack_view = {
          position = "left",
        },
      },
    })

    stack_view.open()
    local context = stack_view_context()
    assert.is_not_nil(context)

    local win_cfg = vim.api.nvim_win_get_config(context.winid)
    assert.equals("editor", win_cfg.relative)
    assert.equals(0, win_cfg.col)
    assert.equals(0, win_cfg.row)
  end)

  it("opens stack view at the bottom when configured", function()
    config.setup({
      ui = {
        stack_view = {
          position = "bottom",
        },
      },
    })

    stack_view.open()
    local context = stack_view_context()
    assert.is_not_nil(context)

    local win_cfg = vim.api.nvim_win_get_config(context.winid)
    assert.equals("editor", win_cfg.relative)
    assert.equals(0, win_cfg.col)
    assert.equals(vim.o.columns, win_cfg.width)
    assert.is_true(win_cfg.row > 0)
  end)

  it("binds stack view keymaps to the buffer", function()
    set_stack_items({
      { id = 1, title = "Alpha", location = location_for("/tmp/alpha.lua"), pinned = false },
    })

    stack_view.open()
    local context = stack_view_context()
    assert.is_not_nil(context)

    local keymaps = vim.api.nvim_buf_get_keymap(context.bufnr, "n")
    local bound = {}
    for _, keymap in ipairs(keymaps) do
      bound[keymap.lhs] = true
    end

    assert.is_true(bound["U"] == true, "U keymap should be bound in stack view")
    assert.is_true(bound["H"] == true, "H keymap should be bound in stack view")
  end)

  it("moves cursor by stack item with j and k, skipping preview lines", function()
    local source = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "local alpha = 1", "local beta = 2", "local gamma = 3" })
    local function item(id, title, line)
      local loc = location_for("/tmp/" .. title .. ".lua")
      loc.range.start.line = line
      loc.range["end"].line = line
      return { id = id, title = title, location = loc, source_bufnr = source, pinned = false }
    end
    set_stack_items({ item(1, "Alpha", 0), item(2, "Beta", 1), item(3, "Gamma", 2) })

    local ok, err = pcall(function()
      stack_view.open()
      local context = stack_view_context()
      assert.is_not_nil(context)

      -- Each item renders its title line followed by one preview line.
      local lines = vim.api.nvim_buf_get_lines(context.bufnr, 0, -1, false)
      assert.equals(7, #lines)
      assert.is_truthy(lines[2]:find("Alpha", 1, true))
      assert.is_truthy(lines[3]:find("local alpha = 1", 1, true))
      assert.is_truthy(lines[4]:find("Beta", 1, true))
      assert.is_truthy(lines[6]:find("Gamma", 1, true))

      vim.api.nvim_set_current_win(context.winid)
      local function press(keys)
        vim.api.nvim_feedkeys(keys, "mx", false)
        return vim.api.nvim_win_get_cursor(context.winid)[1]
      end

      vim.api.nvim_win_set_cursor(context.winid, { 2, 0 })
      assert.equals(4, press("j"))
      assert.equals(6, press("j"))
      -- Stays on the last item.
      assert.equals(6, press("j"))
      assert.equals(4, press("k"))
      assert.equals(2, press("k"))
      -- Stays on the first item.
      assert.equals(2, press("k"))

      -- A count moves by that many items.
      assert.equals(6, press("2j"))
      assert.equals(2, press("2k"))

      -- From a preview line, k moves to the previous item, not to its own title.
      vim.api.nvim_win_set_cursor(context.winid, { 5, 0 })
      assert.equals(2, press("k"))
      vim.api.nvim_win_set_cursor(context.winid, { 3, 0 })
      assert.equals(4, press("j"))
    end)

    pcall(vim.api.nvim_buf_delete, source, { force = true })
    if not ok then
      error(err)
    end
  end)

  it("does not allow cursor on the stack header line", function()
    set_stack_items({
      { id = 1, title = "Alpha", location = location_for("/tmp/alpha.lua"), pinned = false },
    })

    stack_view.open()
    local context = stack_view_context()
    assert.is_not_nil(context)

    vim.api.nvim_set_current_win(context.winid)
    vim.api.nvim_feedkeys("gg", "mx", false)
    vim.wait(50, function()
      return vim.api.nvim_win_get_cursor(context.winid)[1] == 2
    end)

    assert.equals(2, vim.api.nvim_win_get_cursor(context.winid)[1])
  end)

  ---Open a real file in the current window and return a location builder for it.
  ---@return fun(line: integer): PeekstackLocation, fun()
  local function open_source_file()
    local path = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "local one = 1", "local two = 2", "local three = 3" }, path)
    vim.api.nvim_cmd({ cmd = "edit", args = { path } }, {})
    local bufnr = vim.api.nvim_get_current_buf()
    local function at(line)
      return helpers.make_location({
        uri = vim.uri_from_fname(path),
        range = { start = { line = line, character = 0 }, ["end"] = { line = line, character = 0 } },
      })
    end
    local function cleanup()
      close_floating_windows()
      stack._reset()
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      vim.fn.delete(path)
    end
    return at, cleanup
  end

  it("restores the last closed popup with u and returns focus to stack view", function()
    local at, cleanup = open_source_file()
    local root_winid = vim.api.nvim_get_current_win()

    local ok, err = pcall(function()
      local model = stack.push(at(1))
      assert.is_not_nil(model)
      stack.close(model.id)
      assert.equals(0, #stack.list(root_winid))
      assert.equals(1, #stack.history_list(root_winid))

      stack_view.open()
      local context = stack_view_context()
      assert.is_not_nil(context)
      assert.equals(root_winid, context.root_winid)

      vim.api.nvim_set_current_win(context.winid)
      vim.api.nvim_feedkeys("u", "mx", false)

      local popups = stack.list(root_winid)
      assert.equals(1, #popups)
      assert.equals(0, #stack.history_list(root_winid))
      assert.equals(at(1).uri, popups[1].location.uri)
      assert.equals(1, popups[1].location.range.start.line)
      assert.is_true(vim.api.nvim_win_is_valid(popups[1].winid))
      assert.equals(2, vim.api.nvim_win_get_cursor(popups[1].winid)[1])

      -- The panel re-renders with the restored popup and keeps focus.
      local lines = vim.api.nvim_buf_get_lines(context.bufnr, 0, -1, false)
      assert.is_truthy(lines[1]:find("Stack: 1", 1, true))
      assert.equals(context.winid, vim.api.nvim_get_current_win())
    end)

    cleanup()
    if not ok then
      error(err)
    end
  end)

  it("restores the selected history entry with H and returns focus to stack view", function()
    local at, cleanup = open_source_file()
    local root_winid = vim.api.nvim_get_current_win()
    local original_select = vim.ui.select

    local ok, err = pcall(function()
      local first = stack.push(at(0))
      local second = stack.push(at(2))
      assert.is_not_nil(first)
      assert.is_not_nil(second)
      stack.close(second.id)
      stack.close(first.id)
      assert.equals(0, #stack.list(root_winid))
      assert.equals(2, #stack.history_list(root_winid))

      stack_view.open()
      local context = stack_view_context()
      assert.is_not_nil(context)

      local offered = nil
      vim.ui.select = function(items, _opts, on_choice)
        offered = items
        -- Pick the entry for line 2, which is not the most recently closed one.
        for _, choice in ipairs(items) do
          if choice.entry.location.range.start.line == 2 then
            on_choice(choice)
            return
          end
        end
        on_choice(nil)
      end

      vim.api.nvim_set_current_win(context.winid)
      vim.api.nvim_feedkeys("H", "mx", false)

      assert.equals(2, #offered)
      local popups = stack.list(root_winid)
      assert.equals(1, #popups)
      assert.equals(2, popups[1].location.range.start.line)
      assert.is_true(vim.api.nvim_win_is_valid(popups[1].winid))

      local remaining = stack.history_list(root_winid)
      assert.equals(1, #remaining)
      assert.equals(0, remaining[1].location.range.start.line)

      assert.equals(context.winid, vim.api.nvim_get_current_win())
    end)

    vim.ui.select = original_select
    cleanup()
    if not ok then
      error(err)
    end
  end)

  it("resolves correct root winid from a floating popup window", function()
    local window = require("peekstack.ui.stack_view.window")

    -- Create two splits
    local win_a = vim.api.nvim_get_current_win()
    vim.api.nvim_cmd({ cmd = "vsplit" }, {})
    local win_b = vim.api.nvim_get_current_win()

    -- Push a popup from win_a
    vim.api.nvim_set_current_win(win_a)
    local model = stack.push(helpers.make_location())
    assert.is_not_nil(model)

    -- Focus the popup (a floating window)
    vim.api.nvim_set_current_win(model.winid)

    -- find_root_winid should resolve to win_a (the root that owns the popup),
    -- not to win_b (an unrelated split)
    local resolved = window.find_root_winid()
    assert.equals(win_a, resolved)

    -- Cleanup
    stack.close(model.id)
    pcall(vim.api.nvim_win_close, win_b, true)
  end)

  it("closes help when focus leaves the help window", function()
    stack_view.open()
    local context = stack_view_context()
    assert.is_not_nil(context)

    vim.api.nvim_set_current_win(context.winid)
    vim.api.nvim_feedkeys("?", "mx", false)
    vim.wait(50, function()
      local help = help_context()
      return help ~= nil and vim.api.nvim_win_is_valid(help.winid)
    end)

    local help = help_context()
    assert.is_not_nil(help)

    vim.api.nvim_set_current_win(context.root_winid)
    vim.wait(50, function()
      return help_context() == nil
    end)

    assert.is_nil(help_context())
  end)
end)
