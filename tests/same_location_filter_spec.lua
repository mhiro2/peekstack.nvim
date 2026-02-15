local peekstack = require("peekstack")
local stack = require("peekstack.core.stack")
local config = require("peekstack.config")
local helpers = require("tests.helpers")

describe("same location filter", function()
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

  local function set_cursor(line, col)
    vim.api.nvim_win_set_cursor(0, { line, col })
  end

  it("filters same position for lsp providers", function()
    set_cursor(1, 0)
    local loc_same = helpers.make_location({
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
    })

    peekstack.register_provider("lsp.test_filter", function(_ctx, cb)
      cb({ loc_same })
    end)

    peekstack.peek("lsp.test_filter", {})

    local stack_list = stack.list()
    assert.equals(0, #stack_list)
  end)

  it("filters when cursor is within the location range", function()
    set_cursor(1, 5)
    local loc_same = helpers.make_location({
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    })

    peekstack.register_provider("lsp.test_filter_range", function(_ctx, cb)
      cb({ loc_same })
    end)

    peekstack.peek("lsp.test_filter_range", {})

    local stack_list = stack.list()
    assert.equals(0, #stack_list)
  end)

  it("keeps non-matching locations for lsp providers", function()
    set_cursor(1, 0)
    local loc_same = helpers.make_location({
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
    })
    local loc_other = helpers.make_location({
      range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 0 } },
    })

    peekstack.register_provider("lsp.test_filter_multi", function(_ctx, cb)
      cb({ loc_same, loc_other })
    end)

    peekstack.peek("lsp.test_filter_multi", {})

    local stack_list = stack.list()
    assert.equals(1, #stack_list)
    assert.equals(loc_other.uri, stack_list[1].location.uri)
    assert.equals(loc_other.range.start.line, stack_list[1].location.range.start.line)
  end)

  it("does not filter for non-lsp providers", function()
    set_cursor(1, 0)
    local loc_same = helpers.make_location({
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
    })

    peekstack.register_provider("diagnostics.test_filter", function(_ctx, cb)
      cb({ loc_same })
    end)

    peekstack.peek("diagnostics.test_filter", {})

    local stack_list = stack.list()
    assert.equals(1, #stack_list)
  end)

  it("filters same position for lsp.symbols_document provider", function()
    set_cursor(1, 0)
    local loc_same = helpers.make_location({
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
    })

    peekstack.register_provider("lsp.symbols_document", function(_ctx, cb)
      cb({ loc_same })
    end)

    peekstack.peek("lsp.symbols_document", {})

    local stack_list = stack.list()
    assert.equals(0, #stack_list)
  end)
end)
