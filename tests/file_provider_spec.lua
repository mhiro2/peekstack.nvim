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
    local tmpdir = vim.fn.tempname()
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
    assert.is_table(result)
    assert.equals(1, #result)
    assert.equals("file.under_cursor", result[1].provider)

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.delete(tmpdir, "rf")
  end)
end)
