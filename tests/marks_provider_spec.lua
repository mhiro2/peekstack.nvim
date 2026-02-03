local config = require("peekstack.config")
local marks_util = require("peekstack.util.marks")

describe("marks provider", function()
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

  before_each(function()
    config.setup({
      providers = {
        marks = {
          enable = true,
          scope = "all",
          include = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
          include_special = false,
        },
      },
    })
  end)

  describe("util.marks.collect", function()
    it("returns empty table when no marks exist", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })

      local locations = marks_util.collect("buffer", bufnr, {
        include = "abcdefghijklmnopqrstuvwxyz",
        include_special = false,
      })
      assert.is_table(locations)
      assert.equals(0, #locations)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("collects local marks with scope buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })
      vim.api.nvim_set_current_buf(bufnr)

      -- Set a local mark
      vim.api.nvim_buf_set_mark(bufnr, "a", 2, 0, {})

      local locations = marks_util.collect("buffer", bufnr, {
        include = "abcdefghijklmnopqrstuvwxyz",
        include_special = false,
      })
      assert.is_table(locations)
      assert.is_true(#locations >= 1)

      -- Verify the mark location structure
      local found = false
      for _, loc in ipairs(locations) do
        if loc.text and loc.text:find("%[a%]") then
          found = true
          assert.equals(1, loc.range.start.line) -- 0-indexed line 2 = 1
          assert.equals(0, loc.range.start.character)
          assert.equals("marks.buffer", loc.provider)
        end
      end
      assert.is_true(found)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("filters marks by include string", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })
      vim.api.nvim_set_current_buf(bufnr)

      vim.api.nvim_buf_set_mark(bufnr, "a", 1, 0, {})
      vim.api.nvim_buf_set_mark(bufnr, "b", 2, 0, {})

      -- Only include mark 'a'
      local locations = marks_util.collect("buffer", bufnr, {
        include = "a",
        include_special = false,
      })

      local has_a = false
      local has_b = false
      for _, loc in ipairs(locations) do
        if loc.text and loc.text:find("%[a%]") then
          has_a = true
        end
        if loc.text and loc.text:find("%[b%]") then
          has_b = true
        end
      end
      assert.is_true(has_a)
      assert.is_false(has_b)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("excludes special marks when include_special is false", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })
      vim.api.nvim_set_current_buf(bufnr)

      -- include_special = false, include has all letters
      local locations = marks_util.collect("buffer", bufnr, {
        include = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'`^.<>[]\"",
        include_special = false,
      })

      -- None of the locations should have special mark characters
      for _, loc in ipairs(locations) do
        if loc.text then
          assert.is_nil(loc.text:match("%['%]"))
          assert.is_nil(loc.text:match("%[`%]"))
          assert.is_nil(loc.text:match("%[%^%]"))
          assert.is_nil(loc.text:match("%[%.%]"))
        end
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns locations with valid structure", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello world", "second line" })
      vim.api.nvim_set_current_buf(bufnr)

      vim.api.nvim_buf_set_mark(bufnr, "a", 1, 3, {})

      local locations = marks_util.collect("buffer", bufnr, {
        include = "a",
        include_special = false,
      })

      assert.is_true(#locations >= 1)
      local loc = locations[1]
      assert.is_string(loc.uri)
      assert.is_table(loc.range)
      assert.is_table(loc.range.start)
      assert.is_table(loc.range["end"])
      assert.is_number(loc.range.start.line)
      assert.is_number(loc.range.start.character)
      assert.is_string(loc.provider)
      assert.is_string(loc.text)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("providers/marks", function()
    it("buffer provider accepts ctx and returns locations", function()
      local marks_provider = require("peekstack.providers.marks")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2" })
      vim.api.nvim_set_current_buf(bufnr)

      local ctx = make_ctx({ bufnr = bufnr })
      local called = false
      marks_provider.buffer(ctx, function(locations)
        called = true
        assert.is_table(locations)
      end)
      assert.is_true(called)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("global provider accepts ctx and returns locations", function()
      local marks_provider = require("peekstack.providers.marks")
      local ctx = make_ctx()
      local called = false
      marks_provider.global(ctx, function(locations)
        called = true
        assert.is_table(locations)
      end)
      assert.is_true(called)
    end)

    it("all provider accepts ctx and returns locations", function()
      local marks_provider = require("peekstack.providers.marks")
      local ctx = make_ctx()
      local called = false
      marks_provider.all(ctx, function(locations)
        called = true
        assert.is_table(locations)
      end)
      assert.is_true(called)
    end)
  end)
end)
