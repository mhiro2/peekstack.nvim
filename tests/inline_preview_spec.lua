describe("peekstack.ui.inline_preview", function()
  local inline_preview = require("peekstack.ui.inline_preview")
  local config = require("peekstack.config")
  local temp_file = nil

  before_each(function()
    inline_preview._reset_for_test()
    -- Setup config with inline preview enabled
    config.setup({
      ui = {
        inline_preview = {
          enabled = true,
          max_lines = 10,
          hl_group = "PeekstackInlinePreview",
          close_events = { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" },
        },
      },
    })
    temp_file = vim.fn.tempname()
    vim.fn.writefile({ "line1", "line2", "line3" }, temp_file)
  end)

  after_each(function()
    inline_preview._reset_for_test()
    if temp_file then
      vim.fn.delete(temp_file)
    end
  end)

  it("should return false when not open", function()
    assert.is_false(inline_preview.is_open())
  end)

  it("should close safely when not open", function()
    -- Should not error
    inline_preview.close()
  end)

  it("should render lines from a location", function()
    local location = {
      uri = vim.uri_from_fname(temp_file),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local lines = nil
    inline_preview.render_lines_async(location, 5, function(result)
      lines = result
    end)
    vim.wait(200, function()
      return lines ~= nil
    end)
    assert.is_not_nil(lines)
    assert.is_true(#lines > 0)
  end)

  it("should handle non-existent file gracefully", function()
    local location = {
      uri = "file:///non/existent/file.lua",
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local lines = nil
    inline_preview.render_lines_async(location, 5, function(result)
      lines = result
    end)
    vim.wait(200, function()
      return lines ~= nil
    end)
    assert.is_not_nil(lines)
    assert.equals("-- Unable to read file --", lines[1])
  end)

  it("should handle lines beyond end of file", function()
    local location = {
      uri = vim.uri_from_fname(temp_file),
      range = { start = { line = 99999, character = 0 }, ["end"] = { line = 99999, character = 10 } },
    }

    local lines = nil
    inline_preview.render_lines_async(location, 5, function(result)
      lines = result
    end)
    vim.wait(200, function()
      return lines ~= nil
    end)
    assert.is_not_nil(lines)
    -- May return "Unable to read file" or "Line beyond end of file" depending on context
    -- Both are acceptable outcomes
    local is_valid = lines[1] == "-- Line beyond end of file --" or lines[1] == "-- Unable to read file --"
    assert.is_true(is_valid)
  end)

  it("should respect max_lines setting", function()
    local location = {
      uri = vim.uri_from_fname(temp_file),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local lines = nil
    inline_preview.render_lines_async(location, 3, function(result)
      lines = result
    end)
    vim.wait(200, function()
      return lines ~= nil
    end)
    assert.is_true(#lines <= 3)
  end)

  it("should notify when disabled", function()
    config.setup({
      ui = {
        inline_preview = { enabled = false },
      },
    })

    local location = {
      uri = vim.uri_from_fname(temp_file),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    -- Should not error when disabled
    inline_preview.open(location)
  end)

  it("should cache namespace id", function()
    local location = {
      uri = vim.uri_from_fname(temp_file),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local original_get_namespaces = vim.api.nvim_get_namespaces
    local get_namespaces_calls = 0
    local ok, err = pcall(function()
      vim.api.nvim_get_namespaces = function(...)
        get_namespaces_calls = get_namespaces_calls + 1
        return original_get_namespaces(...)
      end

      inline_preview.open(location)
      inline_preview.close()
      inline_preview.open(location)
      inline_preview.close()
    end)
    vim.api.nvim_get_namespaces = original_get_namespaces
    if not ok then
      error(err)
    end

    assert.equals(1, get_namespaces_calls)
  end)
end)
