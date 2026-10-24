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

  it("prefers the exact provider icon over the category icon", function()
    config.setup({
      ui = {
        title = {
          icons = { enabled = true, map = { lsp = "L ", ["lsp.definition"] = "D " } },
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

    local icon_chunks = {}
    for _, chunk in ipairs(model.win_opts.title or {}) do
      if type(chunk) == "table" and chunk[2] == "PeekstackTitleIcon" then
        table.insert(icon_chunks, chunk[1])
      end
    end

    popup.close(model)
    vim.fn.delete(tmpfile)

    assert.are.same({ "D " }, icon_chunks)
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

  describe("truncate_chunks", function()
    local render = require("peekstack.ui.render")

    ---@param chunks PeekstackTitleChunk[]
    ---@return string
    local function joined(chunks)
      local parts = {}
      for _, chunk in ipairs(chunks) do
        table.insert(parts, chunk[1])
      end
      return table.concat(parts)
    end

    it("keeps both ends and their highlights within max_width", function()
      local chunks = render.truncate_chunks({ { "lsp.refs ", "Provider" }, { "path/to/file.lua", "Path" } }, 12)
      assert.same({ { "lsp.r", "Provider" }, { "..." }, { ".lua", "Path" } }, chunks)
    end)

    it("splits kept ends across chunk boundaries", function()
      local chunks = render.truncate_chunks({ { "ab", "A" }, { "cdefghij", "B" }, { "kl", "C" } }, 9)
      assert.same({ { "ab", "A" }, { "c", "B" }, { "..." }, { "j", "B" }, { "kl", "C" } }, chunks)
    end)

    it("measures a tab on the right at the column it lands on", function()
      local chunks = render.truncate_chunks({ { "123456789ZZZZZZ", "A" }, { "abcdefg\tx", "B" } }, 21)
      assert.same({ { "123456789", "A" }, { "..." }, { "efg\tx", "B" } }, chunks)
    end)

    it("budgets wide characters by display cells", function()
      local chunks =
        render.truncate_chunks({ { "定義 ", "Provider" }, { "日本語のファイル名.lua", "Path" } }, 14)
      assert.equals(14, vim.fn.strdisplaywidth(joined(chunks)))
      -- 11 cells remain. The left gets 6 but "日" does not fit in the sixth, so
      -- that cell lets "名" join ".lua" on the right.
      assert.same({ { "定義 ", "Provider" }, { "..." }, { "名.lua", "Path" } }, chunks)

      local narrow = render.truncate_chunks({ { "日本語のファイル名", "Path" } }, 8)
      assert.is_true(vim.fn.strdisplaywidth(joined(narrow)) <= 8, joined(narrow))
      assert.same({ { "日", "Path" }, { "..." }, { "名", "Path" } }, narrow)
    end)
  end)
end)
