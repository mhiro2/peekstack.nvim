describe("peekstack.ui.render", function()
  local popup = require("peekstack.core.popup")
  local config = require("peekstack.config")

  before_each(function()
    config.setup({})
    popup._reset()
  end)

  after_each(function()
    popup._reset()
  end)

  it("builds structured titles with provider/path highlights", function()
    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "line1" }, tmpfile)

    local loc = {
      uri = vim.uri_from_fname(tmpfile),
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 4 },
      },
      provider = "lsp.definition",
    }

    local model = popup.create(loc)
    assert.is_not_nil(model)
    assert.equals("table", type(model.win_opts.title))
    assert.equals("string", type(model.title))

    local has_provider = false
    local has_path = false
    for _, chunk in ipairs(model.win_opts.title or {}) do
      if type(chunk) == "table" then
        if chunk[2] == "PeekstackTitleProvider" then
          has_provider = true
        end
        if chunk[2] == "PeekstackTitlePath" then
          has_path = true
        end
      end
    end

    assert.is_true(has_provider)
    assert.is_true(has_path)

    popup.close(model)
    vim.fn.delete(tmpfile)
  end)

  it("includes PeekstackTitleIcon chunk when icons are enabled", function()
    config.setup({
      ui = {
        title = {
          icons = { enabled = true, map = { lsp = " " } },
        },
      },
    })

    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "line1" }, tmpfile)

    local loc = {
      uri = vim.uri_from_fname(tmpfile),
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 4 },
      },
      provider = "lsp.definition",
    }

    local model = popup.create(loc)
    assert.is_not_nil(model)

    local has_icon = false
    for _, chunk in ipairs(model.win_opts.title or {}) do
      if type(chunk) == "table" and chunk[2] == "PeekstackTitleIcon" then
        has_icon = true
      end
    end

    assert.is_true(has_icon)

    popup.close(model)
    vim.fn.delete(tmpfile)
  end)

  it("omits icon chunk when icons are disabled", function()
    config.setup({
      ui = {
        title = {
          icons = { enabled = false },
        },
      },
    })

    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "line1" }, tmpfile)

    local loc = {
      uri = vim.uri_from_fname(tmpfile),
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 4 },
      },
      provider = "lsp.definition",
    }

    local model = popup.create(loc)
    assert.is_not_nil(model)

    local has_icon = false
    for _, chunk in ipairs(model.win_opts.title or {}) do
      if type(chunk) == "table" and chunk[2] == "PeekstackTitleIcon" then
        has_icon = true
      end
    end

    assert.is_false(has_icon)

    popup.close(model)
    vim.fn.delete(tmpfile)
  end)

  it("falls back to category icon when exact provider not in map", function()
    config.setup({
      ui = {
        title = {
          icons = { enabled = true, map = { lsp = " " } },
        },
      },
    })

    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "line1" }, tmpfile)

    local loc = {
      uri = vim.uri_from_fname(tmpfile),
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 4 },
      },
      provider = "lsp.unknown_method",
    }

    local model = popup.create(loc)
    assert.is_not_nil(model)

    local icon_text = nil
    for _, chunk in ipairs(model.win_opts.title or {}) do
      if type(chunk) == "table" and chunk[2] == "PeekstackTitleIcon" then
        icon_text = chunk[1]
      end
    end

    assert.is_not_nil(icon_text)
    assert.equals(" ", icon_text)

    popup.close(model)
    vim.fn.delete(tmpfile)
  end)

  it("applies PeekstackTitleLine highlight to line number", function()
    config.setup({})

    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "line1" }, tmpfile)

    local loc = {
      uri = vim.uri_from_fname(tmpfile),
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 4 },
      },
      provider = "lsp.definition",
    }

    local model = popup.create(loc)
    assert.is_not_nil(model)

    local has_line_hl = false
    for _, chunk in ipairs(model.win_opts.title or {}) do
      if type(chunk) == "table" and chunk[2] == "PeekstackTitleLine" then
        has_line_hl = true
      end
    end

    assert.is_true(has_line_hl)

    popup.close(model)
    vim.fn.delete(tmpfile)
  end)
end)
