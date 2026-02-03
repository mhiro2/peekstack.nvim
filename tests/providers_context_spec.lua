describe("providers with context", function()
  local config = require("peekstack.config")

  before_each(function()
    config.setup({})
  end)

  local function make_ctx(overrides)
    return vim.tbl_extend("force", {
      winid = vim.api.nvim_get_current_win(),
      bufnr = vim.api.nvim_get_current_buf(),
      source_bufnr = nil,
      popup_id = nil,
      buffer_mode = nil,
      line_offset = 0,
      position = { line = 0, character = 0 },
      root_winid = vim.api.nvim_get_current_win(),
      from_popup = false,
    }, overrides or {})
  end

  describe("file provider", function()
    it("accepts ctx parameter without error", function()
      local file_provider = require("peekstack.providers.file")
      local ctx = make_ctx()
      local called = false
      file_provider.under_cursor(ctx, function(locations)
        called = true
        assert.is_table(locations)
      end)
      assert.is_true(called)
    end)

    it("resolves path from ctx.bufnr", function()
      local file_provider = require("peekstack.providers.file")
      -- Create a temp file to use as source buffer
      local tmpfile = vim.fn.tempname() .. ".lua"
      vim.fn.writefile({ "-- test" }, tmpfile)
      local bufnr = vim.fn.bufadd(tmpfile)
      vim.fn.bufload(bufnr)

      local ctx = make_ctx({ bufnr = bufnr })
      -- The provider should not error when resolving paths from ctx.bufnr
      file_provider.under_cursor(ctx, function(locations)
        assert.is_table(locations)
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
      vim.fn.delete(tmpfile)
    end)
  end)

  describe("diagnostics provider", function()
    it("accepts ctx parameter for under_cursor", function()
      local diag_provider = require("peekstack.providers.diagnostics")
      local ctx = make_ctx()
      local called = false
      diag_provider.under_cursor(ctx, function(locations)
        called = true
        assert.is_table(locations)
      end)
      assert.is_true(called)
    end)

    it("accepts ctx parameter for in_buffer", function()
      local diag_provider = require("peekstack.providers.diagnostics")
      local ctx = make_ctx()
      local called = false
      diag_provider.in_buffer(ctx, function(locations)
        called = true
        assert.is_table(locations)
      end)
      assert.is_true(called)
    end)

    it("uses ctx.bufnr for diagnostic lookup", function()
      local diag_provider = require("peekstack.providers.diagnostics")
      local bufnr = vim.api.nvim_create_buf(false, true)
      local ctx = make_ctx({ bufnr = bufnr, position = { line = 0, character = 0 } })

      diag_provider.under_cursor(ctx, function(locations)
        -- No diagnostics expected on empty buffer, but no error
        assert.is_table(locations)
        assert.equals(0, #locations)
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("grep provider", function()
    it("accepts ctx parameter", function()
      local grep_provider = require("peekstack.providers.grep")
      assert.is_function(grep_provider.search)
    end)
  end)
end)
