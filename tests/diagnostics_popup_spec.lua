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
