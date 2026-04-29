describe("peekstack.core.popup.buffer", function()
  local buffer = require("peekstack.core.popup.buffer")
  local config = require("peekstack.config")

  local temp_paths = {}
  local temp_bufnrs = {}

  local function cleanup_temp_buffers()
    for _, bufnr in ipairs(temp_bufnrs) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
    temp_bufnrs = {}
  end

  local function cleanup_temp_files()
    for _, path in ipairs(temp_paths) do
      pcall(vim.fn.delete, path)
    end
    temp_paths = {}
  end

  ---@param lines string[]
  ---@return string
  local function make_file(lines)
    local path = vim.fn.tempname() .. ".lua"
    vim.fn.writefile(lines, path)
    temp_paths[#temp_paths + 1] = path
    return path
  end

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

  before_each(function()
    config.setup({})
  end)

  after_each(function()
    cleanup_temp_buffers()
    cleanup_temp_files()
  end)

  it("prepares a scratch buffer in copy mode", function()
    local path = make_file({ "alpha", "beta", "gamma" })
    local prepared = buffer.prepare(make_location(path, 1), { buffer_mode = "copy" })

    assert.is_not_nil(prepared)
    temp_bufnrs[#temp_bufnrs + 1] = prepared.bufnr
    temp_bufnrs[#temp_bufnrs + 1] = prepared.source_bufnr

    assert.equals("copy", prepared.buffer_mode)
    assert.is_not.equals(prepared.source_bufnr, prepared.bufnr)
    assert.equals("nofile", vim.bo[prepared.bufnr].buftype)
    assert.equals("lua", vim.bo[prepared.bufnr].filetype)
    assert.same({ "alpha", "beta", "gamma" }, vim.api.nvim_buf_get_lines(prepared.bufnr, 0, -1, false))
  end)

  it("windows large buffers around the target line in copy mode", function()
    local lines = {}
    for i = 1, 600 do
      lines[i] = "line" .. i
    end

    local path = make_file(lines)
    local prepared = buffer.prepare(make_location(path, 350), { buffer_mode = "copy" })

    assert.is_not_nil(prepared)
    temp_bufnrs[#temp_bufnrs + 1] = prepared.bufnr
    temp_bufnrs[#temp_bufnrs + 1] = prepared.source_bufnr

    assert.equals(100, prepared.line_offset)
    assert.equals(500, vim.api.nvim_buf_line_count(prepared.bufnr))
    assert.equals("line101", vim.api.nvim_buf_get_lines(prepared.bufnr, 0, 1, false)[1])
    assert.equals("line600", vim.api.nvim_buf_get_lines(prepared.bufnr, 499, 500, false)[1])
    assert.is_not_nil(prepared.viewport)
    assert.equals(600, prepared.viewport.total)
    assert.equals(100, prepared.viewport.skipped_before)
    assert.equals(0, prepared.viewport.skipped_after)
  end)

  it("reports trailing skipped lines when the target sits near the start", function()
    local lines = {}
    for i = 1, 600 do
      lines[i] = "line" .. i
    end

    local path = make_file(lines)
    local prepared = buffer.prepare(make_location(path, 10), { buffer_mode = "copy" })

    assert.is_not_nil(prepared)
    temp_bufnrs[#temp_bufnrs + 1] = prepared.bufnr
    temp_bufnrs[#temp_bufnrs + 1] = prepared.source_bufnr

    assert.equals(0, prepared.line_offset)
    assert.is_not_nil(prepared.viewport)
    assert.equals(600, prepared.viewport.total)
    assert.equals(0, prepared.viewport.skipped_before)
    assert.equals(100, prepared.viewport.skipped_after)
  end)

  it("does not report a viewport when the source fits in copy mode", function()
    local path = make_file({ "alpha", "beta", "gamma" })
    local prepared = buffer.prepare(make_location(path, 1), { buffer_mode = "copy" })

    assert.is_not_nil(prepared)
    temp_bufnrs[#temp_bufnrs + 1] = prepared.bufnr
    temp_bufnrs[#temp_bufnrs + 1] = prepared.source_bufnr

    assert.is_nil(prepared.viewport)
  end)

  it("reuses the source buffer in source mode", function()
    local path = make_file({ "source buffer" })
    local prepared = buffer.prepare(make_location(path, 0), { buffer_mode = "source" })

    assert.is_not_nil(prepared)
    temp_bufnrs[#temp_bufnrs + 1] = prepared.bufnr

    assert.equals("source", prepared.buffer_mode)
    assert.equals(prepared.source_bufnr, prepared.bufnr)
    assert.equals(0, prepared.line_offset)
    assert.is_not.equals("nofile", vim.bo[prepared.bufnr].buftype)
    assert.is_nil(prepared.viewport)
  end)
end)
