describe("popup source mode", function()
  local popup = require("peekstack.core.popup")
  local config = require("peekstack.config")
  local stack = require("peekstack.core.stack")

  before_each(function()
    popup._reset()
    stack._reset()
    config.setup({})
  end)

  after_each(function()
    stack._reset()
    popup._reset()
  end)

  local function make_location()
    return {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }
  end

  it("creates popup in copy mode by default", function()
    local loc = make_location()
    local model = popup.create(loc)
    assert.is_not_nil(model)
    assert.equals("copy", model.buffer_mode)
    assert.is_true(model.bufnr ~= model.source_bufnr)
    popup.close(model)
  end)

  it("creates popup in source mode when opts.buffer_mode is source", function()
    local loc = make_location()
    local model = popup.create(loc, { buffer_mode = "source" })
    assert.is_not_nil(model)
    assert.equals("source", model.buffer_mode)
    assert.equals(model.source_bufnr, model.bufnr)
    popup.close(model)
  end)

  it("creates popup in source mode when config default is source", function()
    config.setup({ ui = { popup = { buffer_mode = "source" } } })
    local loc = make_location()
    local model = popup.create(loc)
    assert.is_not_nil(model)
    assert.equals("source", model.buffer_mode)
    assert.equals(model.source_bufnr, model.bufnr)
    popup.close(model)
  end)

  it("opts.buffer_mode overrides config default", function()
    config.setup({ ui = { popup = { buffer_mode = "source" } } })
    local loc = make_location()
    local model = popup.create(loc, { buffer_mode = "copy" })
    assert.is_not_nil(model)
    assert.equals("copy", model.buffer_mode)
    assert.is_true(model.bufnr ~= model.source_bufnr)
    popup.close(model)
  end)

  it("source mode buffer is the real file buffer", function()
    local loc = make_location()
    local model = popup.create(loc, { buffer_mode = "source" })
    assert.is_not_nil(model)
    -- buftype should NOT be "nofile" for source mode
    assert.is_true(vim.bo[model.bufnr].buftype ~= "nofile")
    popup.close(model)
  end)

  it("copy mode buffer is a scratch buffer", function()
    local loc = make_location()
    local model = popup.create(loc, { buffer_mode = "copy" })
    assert.is_not_nil(model)
    assert.equals("nofile", vim.bo[model.bufnr].buftype)
    popup.close(model)
  end)
end)
