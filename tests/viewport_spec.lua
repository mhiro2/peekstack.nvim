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

  it("wipes the copy buffer together with its markers on close", function()
    local lines = {}
    for i = 1, 600 do
      lines[i] = "line" .. i
    end
    local tmpfile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile(lines, tmpfile)

    local model = popup.create(make_location(tmpfile, 350), { buffer_mode = "copy" })
    assert.is_not_nil(model)
    assert.is_not_nil(model.viewport_marks)

    local bufnr = model.bufnr
    popup.close(model)

    assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
    vim.fn.delete(tmpfile)
  end)

  describe("decorate and clear", function()
    local viewport = require("peekstack.ui.viewport")
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two", "three" })
    end)

    after_each(function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    ---@param ns integer
    ---@return table[]
    local function marks_in(ns)
      local result = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
        table.insert(result, {
          id = mark[1],
          row = mark[2],
          text = virt_line_text(mark[4]),
          above = mark[4].virt_lines_above == true,
        })
      end
      return result
    end

    it("marks hidden lines above the first and below the last line", function()
      local marks = viewport.decorate({
        bufnr = bufnr,
        buffer_mode = "copy",
        viewport = { skipped_before = 3, skipped_after = 1 },
      })
      assert.is_not_nil(marks)

      assert.are.same({
        { id = marks.ids[1], row = 0, text = "↑ 3 earlier lines hidden", above = true },
        { id = marks.ids[2], row = 2, text = "↓ 1 later line hidden", above = false },
      }, marks_in(marks.ns))
    end)

    it("clears only the marks it created", function()
      local first = viewport.decorate({
        bufnr = bufnr,
        buffer_mode = "copy",
        viewport = { skipped_before = 3, skipped_after = 2 },
      })
      local second = viewport.decorate({
        bufnr = bufnr,
        buffer_mode = "copy",
        viewport = { skipped_before = 7 },
      })
      local other_ns = vim.api.nvim_create_namespace("peekstack_viewport_test_other")
      local other_id = vim.api.nvim_buf_set_extmark(bufnr, other_ns, 1, 0, {})
      assert.is_not_nil(first)
      assert.is_not_nil(second)
      assert.equals(3, #marks_in(first.ns))

      viewport.clear(first)

      assert.are.same({
        { id = second.ids[1], row = 0, text = "↑ 7 earlier lines hidden", above = true },
      }, marks_in(first.ns))
      assert.are.same({ { other_id, 1, 0 } }, vim.api.nvim_buf_get_extmarks(bufnr, other_ns, 0, -1, {}))
    end)
  end)
end)
