describe("peekstack.providers.file", function()
  local config = require("peekstack.config")
  local file_provider = require("peekstack.providers.file")

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
    config.setup({})
  end)

  it("returns empty when target file does not exist", function()
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    local source = tmpdir .. "/source.lua"
    vim.fn.writefile({ "require('nonexistent_file')" }, source)

    local bufnr = vim.fn.bufadd(source)
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_current_buf(bufnr)

    -- Position cursor on a word that won't resolve to a real file
    vim.api.nvim_win_set_cursor(0, { 1, 10 })

    local result = nil
    file_provider.under_cursor(make_ctx({ bufnr = bufnr }), function(locations)
      result = locations
    end)
    assert.is_table(result)
    assert.equals(0, #result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(tmpdir, "rf")
  end)

  it("returns empty when target is a directory", function()
    local tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    local subdir = tmpdir .. "/subdir"
    vim.fn.mkdir(subdir, "p")
    local source = tmpdir .. "/source.lua"
    vim.fn.writefile({ "subdir" }, source)

    local bufnr = vim.fn.bufadd(source)
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local result = nil
    file_provider.under_cursor(make_ctx({ bufnr = bufnr }), function(locations)
      result = locations
    end)
    assert.is_table(result)
    assert.equals(0, #result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(tmpdir, "rf")
  end)

  it("returns location when target is a valid file", function()
    local tmpdir = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(tmpdir, "p")
    local target = tmpdir .. "/target.lua"
    vim.fn.writefile({ "-- target" }, target)
    local source = tmpdir .. "/source.lua"
    vim.fn.writefile({ "target.lua" }, source)

    local bufnr = vim.fn.bufadd(source)
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local result = nil
    file_provider.under_cursor(make_ctx({ bufnr = bufnr }), function(locations)
      result = locations
    end)
    assert.same({
      {
        uri = vim.uri_from_fname(target),
        range = {
          start = { line = 0, character = 0 },
          ["end"] = { line = 0, character = 0 },
        },
        provider = "file.under_cursor",
      },
    }, result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(tmpdir, "rf")
  end)

  it("resolves a quoted reference without the surrounding punctuation", function()
    local tmpdir = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(tmpdir, "p")
    local target = tmpdir .. "/target.lua"
    vim.fn.writefile({ "-- target" }, target)
    local source = tmpdir .. "/source.lua"
    vim.fn.writefile({ 'dofile("target.lua")' }, source)

    local bufnr = vim.fn.bufadd(source)
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 8 })

    local result = nil
    file_provider.under_cursor(make_ctx({ bufnr = bufnr }), function(locations)
      result = locations
    end)

    assert.same({
      {
        uri = vim.uri_from_fname(target),
        range = {
          start = { line = 0, character = 0 },
          ["end"] = { line = 0, character = 0 },
        },
        provider = "file.under_cursor",
      },
    }, result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(tmpdir, "rf")
  end)

  it("resolves path suffix with line and column", function()
    local tmpdir = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(tmpdir, "p")
    local target = tmpdir .. "/target.lua"
    vim.fn.writefile({ "first", "second", "third", "fourth" }, target)
    local source = tmpdir .. "/source.lua"
    vim.fn.writefile({ "target.lua:3:4" }, source)

    local bufnr = vim.fn.bufadd(source)
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local result = nil
    file_provider.under_cursor(make_ctx({ bufnr = bufnr }), function(locations)
      result = locations
    end)

    assert.same({
      {
        uri = vim.uri_from_fname(target),
        range = {
          start = { line = 2, character = 3 },
          ["end"] = { line = 2, character = 3 },
        },
        provider = "file.under_cursor",
      },
    }, result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(tmpdir, "rf")
  end)

  it("defaults column to 1 when only a line number is present", function()
    local tmpdir = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(tmpdir, "p")
    local target = tmpdir .. "/target.lua"
    vim.fn.writefile({ "first", "second", "third" }, target)
    local source = tmpdir .. "/source.lua"
    vim.fn.writefile({ "target.lua:2" }, source)

    local bufnr = vim.fn.bufadd(source)
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local result = nil
    file_provider.under_cursor(make_ctx({ bufnr = bufnr }), function(locations)
      result = locations
    end)

    assert.same({
      {
        uri = vim.uri_from_fname(target),
        range = {
          start = { line = 1, character = 0 },
          ["end"] = { line = 1, character = 0 },
        },
        provider = "file.under_cursor",
      },
    }, result)

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(tmpdir, "rf")
  end)

  it("resolves a line suffix inside quotes, brackets and trailing punctuation", function()
    local tmpdir = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(tmpdir, "p")
    for _, name in ipairs({ "target.lua", "other-target.lua", "bar.lua", "foo,bar.lua", "foo[bar].lua" }) do
      vim.fn.writefile({ "first", "second", "third" }, tmpdir .. "/" .. name)
    end
    local source = tmpdir .. "/source.lua"

    local cases = {
      { line = '"target.lua:3"', col = 1, lnum = 3, character = 0 },
      { line = "[doc](target.lua:3)", col = 7, lnum = 3, character = 0 },
      { line = "(target.lua:3)", col = 1, lnum = 3, character = 0 },
      { line = "see target.lua:3:2, ok", col = 4, lnum = 3, character = 1 },
      -- The cursor on the line number still resolves the whole reference.
      { line = "see target.lua:3:2, ok", col = 15, lnum = 3, character = 1 },
      -- Of several references in one WORD, the one under the cursor wins.
      { line = "(other-target.lua:1;target.lua:3)", col = 21, lnum = 3, character = 0 },
      { line = "(target.lua:3;other-target.lua:1)", col = 15, lnum = 1, character = 0, file = "other-target.lua" },
      -- Punctuation that belongs to the file name is kept.
      { line = "foo,bar.lua:2", col = 0, lnum = 2, character = 0, file = "foo,bar.lua" },
      { line = "foo[bar].lua:2", col = 0, lnum = 2, character = 0, file = "foo[bar].lua" },
      { line = '"foo,bar.lua:2"', col = 5, lnum = 2, character = 0, file = "foo,bar.lua" },
      -- A reference elsewhere in the WORD does not beat the file under the cursor.
      { line = "[target.lua:2](bar.lua)", col = 17, lnum = 1, character = 0, file = "bar.lua" },
      -- With the cursor on a Markdown link label, the link target is used.
      { line = "[doc](target.lua:3)", col = 2, lnum = 3, character = 0 },
    }
    for _, case in ipairs(cases) do
      vim.fn.writefile({ case.line }, source)
      local bufnr = vim.fn.bufadd(source)
      vim.fn.bufload(bufnr)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, case.col })

      local result = nil
      file_provider.under_cursor(make_ctx({ bufnr = bufnr }), function(locations)
        result = locations
      end)

      assert.same({
        {
          uri = vim.uri_from_fname(tmpdir .. "/" .. (case.file or "target.lua")),
          range = {
            start = { line = case.lnum - 1, character = case.character },
            ["end"] = { line = case.lnum - 1, character = case.character },
          },
          provider = "file.under_cursor",
        },
      }, result, case.line)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end

    vim.fn.delete(tmpdir, "rf")
  end)
end)
