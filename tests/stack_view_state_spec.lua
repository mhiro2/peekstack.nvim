describe("peekstack.ui.stack_view.state", function()
  local config = require("peekstack.config")
  local stack = require("peekstack.core.stack")
  local stack_view = require("peekstack.ui.stack_view")
  local state = require("peekstack.ui.stack_view.state")

  local initial_tabpage = nil

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

  before_each(function()
    initial_tabpage = vim.api.nvim_get_current_tabpage()
    config.setup({})
    stack._reset()
    reset_stack_view_state()
    state.current()
  end)

  after_each(function()
    close_floating_windows()
    close_extra_tabs()
    stack._reset()
    reset_stack_view_state()
  end)

  it("creates distinct autoclose groups per tab", function()
    stack_view.open()
    local first_state = state.current()
    assert.is_not_nil(first_state.autoclose_group)

    vim.api.nvim_cmd({ cmd = "tabnew" }, {})
    stack_view.open()
    local second_state = state.current()
    assert.is_not_nil(second_state.autoclose_group)

    assert.is_true(first_state.autoclose_group ~= second_state.autoclose_group)
  end)

  it("cleans up tab states on tab close", function()
    local initial_count = state.count()

    vim.api.nvim_cmd({ cmd = "tabnew" }, {})
    stack_view.open()
    local tab_state = state.current()
    vim.api.nvim_set_current_win(tab_state.winid)

    vim.api.nvim_feedkeys("?", "nx", false)
    vim.wait(50, function()
      return tab_state.help_winid ~= nil and vim.api.nvim_win_is_valid(tab_state.help_winid)
    end)

    local help_winid = tab_state.help_winid
    vim.api.nvim_cmd({ cmd = "tabclose" }, {})

    vim.wait(50, function()
      return state.count() == initial_count
    end)

    if help_winid then
      assert.is_false(vim.api.nvim_win_is_valid(help_winid))
    end
  end)
end)
