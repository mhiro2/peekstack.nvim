describe("peekstack.ui.viewport", function()
  local popup = require("peekstack.core.popup")
  local config = require("peekstack.config")

  local ns_name = "peekstack_viewport"

  before_each(function()
    config.setup({})
    popup._reset()
  end)

  after_each(function()
    popup._reset()
  end)

  ---@param path string
  ---@param line integer
  ---@return PeekstackLocation
  local function make_location(path, line)
    return {
      uri = vim.uri_from_fname(path),
      range = {
        start = { line = line, character = 0 },
        ["end"] = { line = line, character = 1 },
      },
      provider = "test",
    }
  end

  ---@param details table
  ---@return string?
  local function virt_line_text(details)
    local virt_lines = details and details.virt_lines
    if not virt_lines then
      return nil
    end
    local first = virt_lines[1]
    if not first then
      return nil
    end
    local first_chunk = first[1]
    if not first_chunk then
      return nil
    end
    return first_chunk[1]
  end

  it("adds virt_lines markers when the source is windowed in copy mode", function()
    local lines = {}
    for i = 1, 600 do
      lines[i] = "line" .. i
    end
    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile(lines, tmpfile)

    local model = popup.create(make_location(tmpfile, 350), { buffer_mode = "copy" })
    assert.is_not_nil(model)

    local ns = vim.api.nvim_get_namespaces()[ns_name]
    assert.is_not_nil(ns)
    local marks = vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, { details = true })
    assert.is_true(#marks >= 1)

    local found_above = false
    for _, mark in ipairs(marks) do
      local details = mark[4]
      local text = virt_line_text(details)
      if text and text:find("100", 1, true) and text:find("earlier", 1, true) then
        found_above = true
        assert.is_true(details.virt_lines_above == true)
      end
    end
    assert.is_true(found_above, "expected an 'earlier lines hidden' marker")

    popup.close(model)
    vim.fn.delete(tmpfile)
  end)

  it("does not decorate popups when the source fits in copy mode", function()
    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "alpha", "beta", "gamma" }, tmpfile)

    local model = popup.create(make_location(tmpfile, 1), { buffer_mode = "copy" })
    assert.is_not_nil(model)
    assert.is_nil(model.viewport)
    assert.is_nil(model.viewport_marks)

    local ns = vim.api.nvim_get_namespaces()[ns_name]
    if ns then
      local marks = vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, {})
      assert.equals(0, #marks)
    end

    popup.close(model)
    vim.fn.delete(tmpfile)
  end)

  it("does not decorate popups in source mode", function()
    local lines = {}
    for i = 1, 600 do
      lines[i] = "line" .. i
    end
    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile(lines, tmpfile)

    local model = popup.create(make_location(tmpfile, 350), { buffer_mode = "source" })
    assert.is_not_nil(model)
    assert.is_nil(model.viewport_marks)

    local ns = vim.api.nvim_get_namespaces()[ns_name]
    if ns then
      local marks = vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, {})
      assert.equals(0, #marks)
    end

    popup.close(model)
    if vim.api.nvim_buf_is_valid(model.bufnr) then
      vim.api.nvim_buf_delete(model.bufnr, { force = true })
    end
    vim.fn.delete(tmpfile)
  end)

  it("clears extmarks on close", function()
    local lines = {}
    for i = 1, 600 do
      lines[i] = "line" .. i
    end
    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile(lines, tmpfile)

    local model = popup.create(make_location(tmpfile, 350), { buffer_mode = "copy" })
    assert.is_not_nil(model)

    local ns = vim.api.nvim_get_namespaces()[ns_name]
    assert.is_not_nil(ns)
    local before = vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, {})
    assert.is_true(#before > 0)

    local bufnr = model.bufnr
    popup.close(model)

    if vim.api.nvim_buf_is_valid(bufnr) then
      local after = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
      assert.equals(0, #after)
    end

    vim.fn.delete(tmpfile)
  end)
end)
