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
end)
