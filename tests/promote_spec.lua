describe("peekstack.core.promote", function()
  local promote = require("peekstack.core.promote")
  local config = require("peekstack.config")
  local stack = require("peekstack.core.stack")

  local original_close = nil
  local temp_file = nil
  local root_winid = nil

  local function make_popup(id)
    local fname = temp_file
    local uri = vim.uri_from_fname(fname)
    return {
      id = id,
      location = {
        uri = uri,
        range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
        provider = "test",
      },
      origin = { winid = root_winid },
    }
  end

  before_each(function()
    root_winid = vim.api.nvim_get_current_win()
    temp_file = vim.fn.tempname()
    vim.fn.writefile({ "line" }, temp_file)
    original_close = stack.close
  end)

  after_each(function()
    stack.close = original_close
    if temp_file then
      vim.fn.delete(temp_file)
    end
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if winid ~= root_winid then
        pcall(vim.api.nvim_win_close, winid, true)
      end
    end
    if vim.api.nvim_win_is_valid(root_winid) then
      vim.api.nvim_set_current_win(root_winid)
    end
  end)

  it("closes the popup after promote when configured", function()
    config.setup({ ui = { promote = { close_popup = true } } })
    local closed_id = nil
    stack.close = function(id)
      closed_id = id
      return true
    end

    promote.split(make_popup(10))
    assert.equals(10, closed_id)
  end)

  it("does not close the popup when close_popup is false", function()
    config.setup({ ui = { promote = { close_popup = false } } })
    local closed_id = nil
    stack.close = function(id)
      closed_id = id
      return true
    end

    promote.vsplit(make_popup(11))
    assert.is_nil(closed_id)
  end)
end)
