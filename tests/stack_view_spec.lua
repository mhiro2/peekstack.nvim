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
      stack_view.open()
      local context = stack_view_context()
      assert.is_not_nil(context)

      local cfg_before = vim.api.nvim_win_get_config(context.winid)
      vim.o.columns = original_columns + 40
      stack_view.resize_all()

      local cfg_after = vim.api.nvim_win_get_config(context.winid)
      assert.is_true(cfg_after.width >= cfg_before.width)
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

  it("moves cursor by stack item with j and k", function()
    set_stack_items({
      { id = 1, title = "Alpha", location = location_for("/tmp/alpha.lua"), pinned = false },
      { id = 2, title = "Beta", location = location_for("/tmp/beta.lua"), pinned = false },
    })

    stack_view.open()
    local context = stack_view_context()
    assert.is_not_nil(context)

    vim.api.nvim_set_current_win(context.winid)
    vim.api.nvim_win_set_cursor(context.winid, { 3, 0 })

    vim.api.nvim_feedkeys("k", "mx", false)
    vim.wait(50, function()
      return vim.api.nvim_win_get_cursor(context.winid)[1] == 2
    end)
    assert.equals(2, vim.api.nvim_win_get_cursor(context.winid)[1])

    vim.api.nvim_feedkeys("j", "mx", false)
    vim.wait(50, function()
      return vim.api.nvim_win_get_cursor(context.winid)[1] == 3
    end)
    assert.equals(3, vim.api.nvim_win_get_cursor(context.winid)[1])
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

  it("restores focus to stack view after undo close", function()
    local model = stack.push(helpers.make_location())
    assert.is_not_nil(model)
    stack.close(model.id)

    stack_view.open()
    local context = stack_view_context()
    assert.is_not_nil(context)

    vim.api.nvim_set_current_win(context.winid)
    vim.api.nvim_feedkeys("u", "mx", false)
    vim.wait(50, function()
      return vim.api.nvim_get_current_win() == context.winid
    end)

    assert.equals(context.winid, vim.api.nvim_get_current_win())
  end)

  it("restores focus to stack view after history select", function()
    local model = stack.push(helpers.make_location())
    assert.is_not_nil(model)
    stack.close(model.id)

    stack_view.open()
    local context = stack_view_context()
    assert.is_not_nil(context)

    local original_select = vim.ui.select
    local ok, err = pcall(function()
      vim.api.nvim_set_current_win(context.winid)
      vim.ui.select = function(items, _opts, on_choice)
        on_choice(items[1])
      end

      vim.api.nvim_feedkeys("H", "mx", false)
      vim.wait(50, function()
        return vim.api.nvim_get_current_win() == context.winid
      end)

      assert.equals(context.winid, vim.api.nvim_get_current_win())
    end)
    vim.ui.select = original_select

    if not ok then
      error(err)
    end
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
