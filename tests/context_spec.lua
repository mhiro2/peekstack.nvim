describe("context", function()
  local context = require("peekstack.core.context")
  local popup = require("peekstack.core.popup")
  local stack = require("peekstack.core.stack")
  local config = require("peekstack.config")

  before_each(function()
    popup._reset()
    stack._reset()
    config.setup({})
  end)

  after_each(function()
    stack._reset()
    popup._reset()
  end)

  local function make_location(opts)
    return vim.tbl_extend("force", {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }, opts or {})
  end

  describe("normal window", function()
    it("returns from_popup=false", function()
      local ctx = context.current()
      assert.is_false(ctx.from_popup)
      assert.is_nil(ctx.popup_id)
      assert.is_nil(ctx.source_bufnr)
      assert.equals(0, ctx.line_offset)
    end)

    it("returns current bufnr", function()
      local ctx = context.current()
      local expected = vim.api.nvim_get_current_buf()
      assert.equals(expected, ctx.bufnr)
    end)

    it("returns 0-indexed position from cursor", function()
      local ctx = context.current()
      local cursor = vim.api.nvim_win_get_cursor(0)
      assert.equals(cursor[1] - 1, ctx.position.line)
      assert.equals(cursor[2], ctx.position.character)
    end)
  end)

  describe("copy-mode popup", function()
    it("returns from_popup=true with source_bufnr", function()
      local loc = make_location()
      local model = stack.push(loc, { buffer_mode = "copy" })
      assert.is_not_nil(model)
      vim.api.nvim_set_current_win(model.winid)

      local ctx = context.current()
      assert.is_true(ctx.from_popup)
      assert.equals(model.id, ctx.popup_id)
      assert.equals(model.source_bufnr, ctx.bufnr)
      assert.equals(model.source_bufnr, ctx.source_bufnr)
      assert.equals("copy", ctx.buffer_mode)

      stack.close(model.id)
    end)

    it("stores line_offset=0 for small files", function()
      local loc = make_location()
      local model = stack.push(loc)
      assert.is_not_nil(model)
      assert.equals(0, model.line_offset)

      vim.api.nvim_set_current_win(model.winid)
      local ctx = context.current()
      assert.equals(0, ctx.line_offset)

      stack.close(model.id)
    end)
  end)

  describe("source-mode popup", function()
    it("returns from_popup=true with source bufnr", function()
      local loc = make_location()
      local model = stack.push(loc, { buffer_mode = "source" })
      assert.is_not_nil(model)
      vim.api.nvim_set_current_win(model.winid)

      local ctx = context.current()
      assert.is_true(ctx.from_popup)
      assert.equals(model.source_bufnr, ctx.bufnr)
      assert.equals("source", ctx.buffer_mode)
      assert.equals(0, ctx.line_offset)

      stack.close(model.id)
    end)
  end)

  describe("popup markers", function()
    it("sets vim.w and vim.b peekstack_popup_id", function()
      local loc = make_location()
      local model = popup.create(loc)
      assert.is_not_nil(model)

      assert.equals(model.id, vim.w[model.winid].peekstack_popup_id)
      assert.equals(model.id, vim.b[model.bufnr].peekstack_popup_id)

      popup.close(model)
    end)
  end)
end)
