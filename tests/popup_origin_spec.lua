describe("peekstack.core.popup.origin", function()
  local config = require("peekstack.config")
  local origin = require("peekstack.core.popup.origin")
  local popup = require("peekstack.core.popup")
  local stack_view = require("peekstack.ui.stack_view")
  local stack_view_state = require("peekstack.ui.stack_view.state")

  local temp_paths = {}
  local popups = {}

  local function cleanup_popups()
    for i = #popups, 1, -1 do
      local model = popups[i]
      if model.winid and vim.api.nvim_win_is_valid(model.winid) then
        popup.close(model)
      end
    end
    popups = {}
  end

  local function cleanup_stack_view()
    local state = stack_view_state.current()
    if state.winid and vim.api.nvim_win_is_valid(state.winid) then
      stack_view.toggle()
    end
  end

  local function cleanup_temp_files()
    for _, path in ipairs(temp_paths) do
      pcall(vim.fn.delete, path)
    end
    temp_paths = {}
  end

  ---@return PeekstackPopupModel
  local function make_popup()
    local path = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "peekstack" }, path)
    temp_paths[#temp_paths + 1] = path

    local model = popup.create({
      uri = vim.uri_from_fname(path),
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 1 },
      },
      provider = "test",
    })
    assert.is_not_nil(model)
    popups[#popups + 1] = model
    return model
  end

  before_each(function()
    config.setup({})
    popup._reset()
  end)

  after_each(function()
    cleanup_popups()
    cleanup_stack_view()
    cleanup_temp_files()
    popup._reset()
  end)

  it("captures the current window by default", function()
    local winid = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_get_current_buf()
    local captured = origin.capture()

    assert.equals(winid, captured.winid)
    assert.equals(bufnr, captured.bufnr)
    assert.is_false(captured.is_popup)
  end)

  it("marks popup windows as popup origins", function()
    local model = make_popup()
    vim.api.nvim_set_current_win(model.winid)

    local captured = origin.capture()
    assert.is_true(captured.is_popup)
    assert.is_true(origin.is_popup_origin(captured))
  end)

  it("treats stack view windows as popup origins", function()
    stack_view.open()
    local winid = stack_view_state.current().winid
    assert.is_not_nil(winid)
    vim.api.nvim_set_current_win(winid)

    local captured = origin.capture()
    assert.is_false(captured.is_popup)
    assert.is_true(origin.is_popup_origin(captured))
  end)
end)
