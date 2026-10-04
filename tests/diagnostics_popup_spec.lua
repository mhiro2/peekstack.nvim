describe("peekstack.ui.diagnostics", function()
  local popup = require("peekstack.core.popup")
  local config = require("peekstack.config")

  local ns_name = "peekstack_diagnostics"

  before_each(function()
    config.setup({})
    popup._reset()
  end)

  after_each(function()
    popup._reset()
  end)

  ---@param path string
  ---@return PeekstackLocation
  local function make_diagnostic_location(path)
    return {
      uri = vim.uri_from_fname(path),
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 4 },
      },
      provider = "diagnostics.under_cursor",
      text = "example diagnostic message",
      kind = vim.diagnostic.severity.ERROR,
    }
  end

  it("adds virtual lines for diagnostic popups", function()
    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "line1", "line2" }, tmpfile)
    local loc = make_diagnostic_location(tmpfile)
    local model = popup.create(loc)
    assert.is_not_nil(model)
    assert.is_true(model.title:find("example diagnostic message", 1, true) ~= nil)

    local ns = vim.api.nvim_get_namespaces()[ns_name]
    assert.is_not_nil(ns)
    local marks = vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, { details = true })
    local has_virt = false
    for _, mark in ipairs(marks) do
      local details = mark[4]
      if details and details.virt_lines then
        has_virt = true
        break
      end
    end
    assert.is_true(has_virt)

    popup.close(model)
    vim.fn.delete(tmpfile)
  end)

  it("does not error when diagnostic end_col exceeds the line length", function()
    local diagnostics = require("peekstack.ui.diagnostics")
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "ab" })

    local model = {
      bufnr = bufnr,
      line_offset = 0,
      location = {
        provider = "diagnostics.under_cursor",
        text = "boom",
        kind = vim.diagnostic.severity.ERROR,
        range = {
          start = { line = 0, character = 0 },
          ["end"] = { line = 0, character = 999 },
        },
      },
    }

    local ok, result = pcall(diagnostics.decorate, model)
    assert.is_true(ok)
    assert.is_not_nil(result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  describe("underline range", function()
    local diagnostics = require("peekstack.ui.diagnostics")
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    ---@return { row: integer, col: integer, end_row: integer, end_col: integer }?
    local function underline_for(lines, range, line_offset)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      local result = diagnostics.decorate({
        bufnr = bufnr,
        line_offset = line_offset or 0,
        location = {
          provider = "diagnostics.under_cursor",
          text = "boom",
          kind = vim.diagnostic.severity.ERROR,
          range = range,
        },
      })
      assert.is_not_nil(result)
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, result.ns, 0, -1, { details = true })) do
        local details = mark[4]
        if details.hl_group then
          return { row = mark[2], col = mark[3], end_row = details.end_row, end_col = details.end_col }
        end
      end
      return nil
    end

    local function range(sl, sc, el, ec)
      return { start = { line = sl, character = sc }, ["end"] = { line = el, character = ec } }
    end

    it("keeps an end column smaller than the start column on a later line", function()
      local mark = underline_for({ "local value = 1", "abc" }, range(0, 8, 1, 2))
      assert.are.same({ row = 0, col = 8, end_row = 1, end_col = 2 }, mark)
    end)

    it("clamps the end column to the length of a short end line", function()
      local mark = underline_for({ "local value = 1", "abc" }, range(0, 8, 1, 20))
      assert.are.same({ row = 0, col = 8, end_row = 1, end_col = 3 }, mark)
    end)

    it("keeps the start column when the range ends before it on the same line", function()
      local mark = underline_for({ "local value = 1" }, range(0, 8, 0, 2))
      assert.are.same({ row = 0, col = 8, end_row = 0, end_col = 8 }, mark)
    end)

    it("clips a range that starts above the visible lines", function()
      local mark = underline_for({ "visible one", "visible two" }, range(8, 4, 10, 3), 10)
      assert.are.same({ row = 0, col = 0, end_row = 0, end_col = 3 }, mark)
    end)

    it("clips a range that ends below the visible lines", function()
      local mark = underline_for({ "visible one", "visible two" }, range(10, 8, 15, 1), 10)
      assert.are.same({ row = 0, col = 8, end_row = 1, end_col = 11 }, mark)
    end)

    it("does not underline a range entirely outside the visible lines", function()
      assert.is_nil(underline_for({ "visible one", "visible two" }, range(20, 0, 21, 4), 10))
    end)
  end)

  it("clears diagnostic extmarks on close in source mode", function()
    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "line1", "line2" }, tmpfile)
    local loc = make_diagnostic_location(tmpfile)
    local model = popup.create(loc, { buffer_mode = "source" })
    assert.is_not_nil(model)

    local ns = vim.api.nvim_get_namespaces()[ns_name]
    assert.is_not_nil(ns)
    local before = vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, {})
    assert.is_true(#before > 0)

    popup.close(model)

    local after = vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, {})
    assert.equals(0, #after)

    vim.fn.delete(tmpfile)
    if vim.api.nvim_buf_is_valid(model.bufnr) then
      vim.api.nvim_buf_delete(model.bufnr, { force = true })
    end
  end)

  it("truncates diagnostic title path with max_width", function()
    config.setup({ ui = { path = { max_width = 10 } } })
    local tmpdir = string.format("%s/peekstack-title-%d", vim.uv.os_tmpdir(), vim.uv.hrtime())
    local nested = tmpdir .. "/very/long/path/segment"
    assert(vim.uv.fs_mkdir(tmpdir, 448))
    assert(vim.uv.fs_mkdir(tmpdir .. "/very", 448))
    assert(vim.uv.fs_mkdir(tmpdir .. "/very/long", 448))
    assert(vim.uv.fs_mkdir(tmpdir .. "/very/long/path", 448))
    assert(vim.uv.fs_mkdir(nested, 448))

    local tmpfile = nested .. "/a_very_long_filename.lua"
    vim.fn.writefile({ "line1" }, tmpfile)

    local loc = make_diagnostic_location(tmpfile)
    local model = popup.create(loc)
    assert.is_not_nil(model)
    assert.is_true(model.title:find("...", 1, true) ~= nil)

    popup.close(model)
    vim.fn.delete(tmpfile)
    assert(vim.uv.fs_rmdir(nested))
    assert(vim.uv.fs_rmdir(tmpdir .. "/very/long/path"))
    assert(vim.uv.fs_rmdir(tmpdir .. "/very/long"))
    assert(vim.uv.fs_rmdir(tmpdir .. "/very"))
    assert(vim.uv.fs_rmdir(tmpdir))
  end)
end)
