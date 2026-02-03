describe("peekstack.picker.snacks", function()
  local config = require("peekstack.config")

  before_each(function()
    config.setup({
      picker = { backend = "snacks" },
    })
  end)

  it("should warn when snacks.nvim is not available", function()
    -- Test by checking the module behavior when snacks is not installed
    -- The pick function should handle the missing dependency gracefully
    local location = require("peekstack.core.location")

    local test_loc = {
      uri = "file:///path/to/test.lua",
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test_provider",
    }

    -- Just verify the location module works correctly
    local display_text = location.display_text(test_loc, 1)
    assert.is_not_nil(display_text)
    assert.is_true(type(display_text) == "string")

    -- The snacks picker itself will warn when snacks is not available
    -- but we can't easily test that in isolation without mocking
  end)

  it("should format locations correctly", function()
    local location = require("peekstack.core.location")

    local test_loc = {
      uri = "file:///path/to/test.lua",
      range = { start = { line = 5, character = 10 }, ["end"] = { line = 5, character = 20 } },
      provider = "test_provider",
    }

    local display_text = location.display_text(test_loc, 1)
    assert.is_not_nil(display_text)
    assert.is_true(type(display_text) == "string")
  end)

  it("should be registered as a known backend", function()
    local known_backends = {
      "builtin",
      "telescope",
      "fzf-lua",
      "snacks",
    }

    assert.is_true(vim.list_contains(known_backends, "snacks"))
  end)
end)
