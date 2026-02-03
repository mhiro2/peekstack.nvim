describe("peekstack.util.treesitter", function()
  local treesitter = require("peekstack.util.treesitter")
  local config = require("peekstack.config")

  before_each(function()
    config.setup({
      ui = {
        title = {
          context = {
            enabled = true,
            max_depth = 5,
            separator = " • ",
            node_types = {},
          },
        },
      },
    })
  end)

  it("should return nil when context is disabled", function()
    local bufnr = 0
    local line = 0
    local col = 0

    local result = treesitter.context_at(bufnr, line, col, { enabled = false })
    assert.is_nil(result)
  end)

  it("should return nil when parser is not available", function()
    -- Use a buffer that likely doesn't have a parser
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = "unknown_filetype_xyz"

    local result = treesitter.context_at(bufnr, 0, 0, { enabled = true, max_depth = 5 })
    assert.is_nil(result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("should handle invalid buffer gracefully", function()
    local result = treesitter.context_at(-1, 0, 0, { enabled = true, max_depth = 5 })
    assert.is_nil(result)
  end)

  it("should respect max_depth setting", function()
    local bufnr = 0

    -- This should not error
    local result = treesitter.context_at(bufnr, 0, 0, { enabled = true, max_depth = 0 })
    -- With max_depth=0, we should not find anything
    assert.is_nil(result)
  end)

  it("should handle Lua filetypes", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = "lua"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "local function test_function()",
      "  return 42",
      "end",
    })

    -- This should not error even if parser is available
    treesitter.context_at(bufnr, 0, 0, { enabled = true, max_depth = 5 })

    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- Result may be nil if Lua parser is not installed
    -- but should not error
  end)

  it("should return nil for position beyond buffer", function()
    local bufnr = 0
    local line_count = vim.api.nvim_buf_line_count(bufnr)

    local result = treesitter.context_at(bufnr, line_count + 100, 0, { enabled = true, max_depth = 5 })
    assert.is_nil(result)
  end)

  it("should use the provided buffer when extracting node text", function()
    local bufnr_primary = vim.api.nvim_create_buf(false, true)
    local bufnr_other = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr_primary, 0, -1, false, { "alpha" })
    vim.api.nvim_buf_set_lines(bufnr_other, 0, -1, false, { "beta" })
    vim.api.nvim_set_current_buf(bufnr_other)

    local child = {}
    function child:type()
      return "identifier"
    end
    function child:range()
      return 0, 0, 0, 5
    end

    local node = {}
    function node:range()
      return 0, 0, 0, 5
    end
    function node:iter_children()
      local i = 0
      local children = { child }
      return function()
        i = i + 1
        return children[i]
      end
    end

    local result = treesitter._extract_name(node, "function_declaration", bufnr_primary)
    assert.equals("alpha", result)

    vim.api.nvim_buf_delete(bufnr_primary, { force = true })
    vim.api.nvim_buf_delete(bufnr_other, { force = true })
  end)
end)
