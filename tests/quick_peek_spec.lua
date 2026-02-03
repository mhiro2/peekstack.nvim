describe("peekstack.quick_peek", function()
  local stack = require("peekstack.core.stack")
  local config = require("peekstack.config")
  local peekstack = require("peekstack")

  before_each(function()
    stack._reset()
    config.setup({
      ui = {
        quick_peek = {
          close_events = { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" },
        },
      },
    })
  end)

  after_each(function()
    stack._reset()
  end)

  it("should not add to stack when mode is quick", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    local model = stack.push(location, { stack = false })
    assert.is_not_nil(model)
    assert.is_true(model.ephemeral)

    -- The popup should not be in the stack
    local stack_list = stack.list()
    assert.equals(0, #stack_list)
  end)

  it("should set ephemeral flag on quick peek popups", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    local model = stack.push(location, { stack = false })
    assert.is_not_nil(model)
    assert.is_true(model.ephemeral)
  end)

  it("should add to stack normally when mode is not quick", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    local model = stack.push(location, {})
    assert.is_not_nil(model)
    assert.is_false(model.ephemeral)

    -- The popup should be in the stack
    local stack_list = stack.list()
    assert.equals(1, #stack_list)
  end)

  it("should work with peek_location using mode='quick'", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    peekstack.peek_location(location, { mode = "quick" })

    -- The popup should not be in the stack
    local stack_list = stack.list()
    assert.equals(0, #stack_list)
  end)

  it("should work with peek inline mode", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    -- This should not error
    peekstack.peek_location(location, { mode = "inline" })
  end)

  it("should close quick peek popups via stack.close", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    local model = stack.push(location, { stack = false })
    assert.is_not_nil(model)
    assert.is_true(stack.close(model.id))
    assert.is_nil(stack._ephemerals()[model.id])
  end)

  it("should close quick peek popups via close_ephemerals", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    local model = stack.push(location, { stack = false })
    assert.is_not_nil(model)
    stack.close_ephemerals()
    assert.is_nil(stack._ephemerals()[model.id])
  end)

  it("should handle normal peek mode", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    peekstack.peek_location(location, {})

    -- The popup should be in the stack for normal mode
    local stack_list = stack.list()
    assert.equals(1, #stack_list)
  end)
end)
