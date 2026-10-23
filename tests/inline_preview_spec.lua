describe("peekstack.ui.inline_preview", function()
  local inline_preview = require("peekstack.ui.inline_preview")
  local config = require("peekstack.config")
  local temp_file = nil

  before_each(function()
    inline_preview._reset_for_test()
    -- Setup config with inline preview enabled
    config.setup({
      ui = {
        inline_preview = {
          enabled = true,
          max_lines = 10,
          hl_group = "PeekstackInlinePreview",
          close_events = { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" },
        },
      },
    })
    temp_file = vim.fn.tempname()
    vim.fn.writefile({ "line1", "line2", "line3" }, temp_file)
  end)

  after_each(function()
    inline_preview._reset_for_test()
    if temp_file then
      vim.fn.delete(temp_file)
    end
  end)

  it("should return false when not open", function()
    assert.is_false(inline_preview.is_open())
  end)

  it("should close safely when not open", function()
    -- Should not error
    inline_preview.close()
  end)

  ---@param path string
  ---@param line integer 0-based start line
  ---@return PeekstackLocation
  local function location_at(path, line)
    return {
      uri = vim.uri_from_fname(path),
      range = { start = { line = line, character = 0 }, ["end"] = { line = line, character = 0 } },
    }
  end

  ---@param location PeekstackLocation
  ---@param max_lines integer
  ---@return string[]
  local function render(location, max_lines)
    local lines = nil
    inline_preview.render_lines_async(location, max_lines, function(result)
      lines = result
    end)
    local done = vim.wait(1000, function()
      return lines ~= nil
    end)
    assert.is_true(done, "render_lines_async did not complete")
    return lines
  end

  ---@param count integer
  ---@return string[]
  local function numbered_lines(count)
    local lines = {}
    for i = 1, count do
      lines[i] = "line" .. i
    end
    return lines
  end

  it("reads lines from disk starting at the location line and stops at max_lines", function()
    vim.fn.writefile(numbered_lines(10), temp_file)
    assert.equals(-1, vim.fn.bufnr(temp_file))

    assert.same({ "line3", "line4", "line5", "line6" }, render(location_at(temp_file, 2), 4))
  end)

  it("returns the remaining lines when the file ends before max_lines", function()
    -- Binary mode leaves the last line without a trailing newline.
    vim.fn.writefile(numbered_lines(5), temp_file, "b")

    assert.same({ "line4", "line5" }, render(location_at(temp_file, 3), 10))
  end)

  it("joins lines split across read chunks", function()
    local lines = {}
    for i = 1, 6 do
      lines[i] = string.rep(string.char(96 + i), 3000)
    end
    vim.fn.writefile(lines, temp_file)

    assert.same({ lines[2], lines[3], lines[4] }, render(location_at(temp_file, 1), 3))
  end)

  it("reads unsaved content from a loaded buffer", function()
    vim.fn.writefile(numbered_lines(5), temp_file)
    local bufnr = vim.fn.bufadd(temp_file)
    vim.fn.bufload(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 1, 3, false, { "edited2", "edited3" })

    local ok, result = pcall(render, location_at(temp_file, 1), 3)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    assert.is_true(ok, result)
    assert.same({ "edited2", "edited3", "line4" }, result)
  end)

  it("should handle non-existent file gracefully", function()
    assert.same({ "-- Unable to read file --" }, render(location_at("/non/existent/file.lua", 0), 5))
  end)

  it("reports lines beyond the end of an existing file", function()
    assert.same({ "-- Line beyond end of file --" }, render(location_at(temp_file, 99999), 5))
  end)

  it("notifies and does not draw anything when disabled", function()
    config.setup({
      ui = {
        inline_preview = { enabled = false },
      },
    })

    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
    local ok, err = pcall(inline_preview.open, location_at(temp_file, 0))
    vim.notify = original_notify
    assert.is_true(ok, err)

    assert.same({ { msg = "[peekstack] Inline preview is disabled", level = vim.log.levels.INFO } }, notifications)
    assert.is_false(inline_preview.is_open())
    local ns = vim.api.nvim_get_namespaces()["PeekstackInlinePreviewNS"]
    if ns then
      assert.same({}, vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}))
    end
  end)

  it("draws the previewed lines as virtual lines above the cursor", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
    local prev_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    inline_preview.open(location_at(temp_file, 1))
    local ns = vim.api.nvim_get_namespaces()["PeekstackInlinePreviewNS"]
    local function preview_texts()
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      if #marks ~= 1 then
        return nil
      end
      local texts = {}
      for _, virt_line in ipairs(marks[1][4].virt_lines or {}) do
        texts[#texts + 1] = virt_line[1][1]
      end
      return texts, marks[1]
    end
    local done = vim.wait(1000, function()
      local texts = preview_texts()
      return texts ~= nil and texts[1] ~= "Loading... "
    end)

    local texts, mark = preview_texts()
    inline_preview.close()
    vim.api.nvim_set_current_buf(prev_buf)
    vim.api.nvim_buf_delete(bufnr, { force = true })

    assert.is_true(done, "inline preview did not render")
    assert.same({ "line2 ", "line3 " }, texts)
    assert.equals(1, mark[2])
    assert.is_true(mark[4].virt_lines_above)
  end)

  it("should cache namespace id", function()
    local location = {
      uri = vim.uri_from_fname(temp_file),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    local original_get_namespaces = vim.api.nvim_get_namespaces
    local get_namespaces_calls = 0
    local ok, err = pcall(function()
      vim.api.nvim_get_namespaces = function(...)
        get_namespaces_calls = get_namespaces_calls + 1
        return original_get_namespaces(...)
      end

      inline_preview.open(location)
      inline_preview.close()
      inline_preview.open(location)
      inline_preview.close()
    end)
    vim.api.nvim_get_namespaces = original_get_namespaces
    if not ok then
      error(err)
    end

    assert.equals(1, get_namespaces_calls)
  end)

  it("clears the close-event augroup on close to avoid leaking armed autocmds", function()
    local location = {
      uri = vim.uri_from_fname(temp_file),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
    }

    inline_preview.open(location)

    -- Close-event autocmds are registered while the preview is open.
    local armed = vim.api.nvim_get_autocmds({ group = "PeekstackInlinePreview" })
    assert.is_true(#armed > 0)

    inline_preview.close()

    -- After close the augroup must be gone so no `once` autocmds stay armed and
    -- fire on unrelated later events. Querying a deleted group raises.
    local ok, remaining = pcall(vim.api.nvim_get_autocmds, { group = "PeekstackInlinePreview" })
    if ok then
      assert.equals(0, #remaining)
    else
      assert.is_false(ok)
    end
  end)

  it("falls back to default close events when config is invalid", function()
    config.setup({
      ui = {
        inline_preview = {
          enabled = true,
          max_lines = 10,
          hl_group = "PeekstackInlinePreview",
          close_events = "CursorMoved",
        },
      },
    })

    assert.has_no.errors(function()
      inline_preview.setup_close_events()
    end)

    local buf_leave = vim.api.nvim_get_autocmds({
      group = "PeekstackInlinePreview",
      event = "BufLeave",
    })
    local win_leave = vim.api.nvim_get_autocmds({
      group = "PeekstackInlinePreview",
      event = "WinLeave",
    })

    assert.equals(1, #buf_leave)
    assert.equals(1, #win_leave)
  end)
end)
