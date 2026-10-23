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

  -- Only providers in the `lsp.` namespace drop the location under the cursor.
  for _, case in ipairs({
    { provider = "lsp.test_filter", filtered = true },
    { provider = "diagnostics.test_filter", filtered = false },
    { provider = "lsplike.test_filter", filtered = false },
    { provider = "custom.lsp.test_filter", filtered = false },
  }) do
    local verb = case.filtered and "filters" or "does not filter"
    it(("%s the same position for the %s provider"):format(verb, case.provider), function()
      set_cursor(1, 0)
      local loc_same = helpers.make_location({
        range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      })

      peekstack.register_provider(case.provider, function(_ctx, cb)
        cb({ loc_same })
      end)

      peekstack.peek(case.provider, {})

      local stack_list = stack.list()
      assert.equals(case.filtered and 0 or 1, #stack_list)
    end)
  end

  it("filters when cursor is within the location range", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local value = compute()" })
    set_cursor(1, 5)
    -- The cursor really sits inside the range, not on its start.
    assert.same({ 1, 5 }, vim.api.nvim_win_get_cursor(0))

    local loc_around = helpers.make_location({
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    })
    local loc_before = helpers.make_location({
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 4 } },
    })

    peekstack.register_provider("lsp.test_filter_range", function(_ctx, cb)
      cb({ loc_around, loc_before })
    end)

    peekstack.peek("lsp.test_filter_range", {})

    local stack_list = stack.list()
    assert.equals(1, #stack_list)
    assert.same(loc_before.range, stack_list[1].location.range)

    stack.close(stack_list[1].id)
    vim.api.nvim_buf_delete(bufnr, { force = true })
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

  it("keeps a LocationLink whose targetRange contains the cursor", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "function foo()", "  return 1", "end" })
    set_cursor(2, 2)

    peekstack.register_provider("lsp.test_filter_link", function(_ctx, cb)
      cb({
        {
          targetUri = vim.uri_from_bufnr(bufnr),
          targetRange = { start = { line = 0, character = 0 }, ["end"] = { line = 2, character = 3 } },
          targetSelectionRange = { start = { line = 0, character = 9 }, ["end"] = { line = 0, character = 12 } },
        },
      })
    end)

    peekstack.peek("lsp.test_filter_link", {})

    local stack_list = stack.list()
    assert.equals(1, #stack_list)
    assert.same({ line = 0, character = 9 }, stack_list[1].location.range.start)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
