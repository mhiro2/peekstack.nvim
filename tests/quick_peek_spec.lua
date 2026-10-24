describe("peekstack.quick_peek", function()
  local stack = require("peekstack.core.stack")
  local config = require("peekstack.config")
  local peekstack = require("peekstack")

  before_each(function()
    stack._reset()
    config.setup({
      ui = {
        quick_peek = {
          close_events = { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" },
        },
      },
    })
  end)

  after_each(function()
    -- Resetting the state does not close windows, so close leftover popups first.
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(winid).relative ~= "" then
        pcall(vim.api.nvim_win_close, winid, true)
      end
    end
    stack._reset()
  end)

  it("should not add to stack when mode is quick", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    local model = stack.push(location, { stack = false })
    assert.is_not_nil(model)
    assert.is_true(model.ephemeral)

    -- The popup should not be in the stack
    local stack_list = stack.list()
    assert.equals(0, #stack_list)
  end)

  it("should add to stack normally when mode is not quick", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    local model = stack.push(location, {})
    assert.is_not_nil(model)
    assert.is_false(model.ephemeral)

    -- The popup should be in the stack
    local stack_list = stack.list()
    assert.equals(1, #stack_list)
  end)

  it("should work with peek_location using mode='quick'", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    peekstack.peek_location(location, { mode = "quick" })

    -- The popup should not be in the stack
    local stack_list = stack.list()
    assert.equals(0, #stack_list)

    local quick = vim.tbl_values(stack._ephemerals())
    assert.equals(1, #quick)
    local model = quick[1]
    assert.is_true(model.ephemeral)
    assert.equals(location.uri, model.location.uri)
    assert.same(location.range, model.location.range)
    assert.equals("test", model.location.provider)
    assert.is_true(vim.api.nvim_win_is_valid(model.winid))
    assert.is_not.equals("", vim.api.nvim_win_get_config(model.winid).relative)

    assert.is_true(stack.close(model.id))
  end)

  it("should render the target lines with peek inline mode", function()
    local inline_preview = require("peekstack.ui.inline_preview")
    inline_preview._reset_for_test()
    local path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "first line", "second line", "third line" }, path)
    local origin_bufnr = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(origin_bufnr, 0, -1, false, { "origin" })
    local origin_winid = vim.api.nvim_get_current_win()
    local previous_bufnr = vim.api.nvim_win_get_buf(origin_winid)
    vim.api.nvim_win_set_buf(origin_winid, origin_bufnr)
    local wins_before = #vim.api.nvim_list_wins()

    local location = {
      uri = vim.uri_from_fname(path),
      range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 6 } },
      provider = "test",
    }
    peekstack.peek_location(location, { mode = "inline" })

    local ns = vim.api.nvim_get_namespaces().PeekstackInlinePreviewNS
    local function preview_text()
      local text = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(origin_bufnr, ns or -1, 0, -1, { details = true })) do
        for _, virt_line in ipairs(mark[4].virt_lines or {}) do
          for _, chunk in ipairs(virt_line) do
            table.insert(text, chunk[1])
          end
        end
      end
      return table.concat(text, "|")
    end
    local rendered = vim.wait(1000, function()
      return preview_text():find("second line", 1, true) ~= nil
    end, 10)
    local text = preview_text()
    local is_open = inline_preview.is_open()
    inline_preview._reset_for_test()
    if vim.api.nvim_buf_is_valid(previous_bufnr) then
      vim.api.nvim_win_set_buf(origin_winid, previous_bufnr)
    end
    pcall(vim.api.nvim_buf_delete, origin_bufnr, { force = true })
    vim.fn.delete(path)

    assert.is_true(rendered, "inline preview not rendered: " .. text)
    assert.is_nil(text:find("first line", 1, true))
    assert.is_true(is_open)
    assert.equals(0, #stack.list())
    assert.same({}, stack._ephemerals())
    assert.equals(wins_before, #vim.api.nvim_list_wins())
  end)

  it("should close quick peek popups via stack.close", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    local model = stack.push(location, { stack = false })
    assert.is_not_nil(model)
    assert.is_true(stack.close(model.id))
    assert.is_nil(stack._ephemerals()[model.id])
  end)

  it("should close quick peek popups via close_ephemerals", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    local model = stack.push(location, { stack = false })
    assert.is_not_nil(model)
    stack.close_ephemerals()
    assert.is_nil(stack._ephemerals()[model.id])
  end)

  it("keeps split navigation root for quick peek popups", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    vim.api.nvim_cmd({ cmd = "vsplit" }, {})
    vim.api.nvim_cmd({ cmd = "vsplit" }, {})
    vim.api.nvim_cmd({ cmd = "wincmd", args = { "h" } }, {})
    vim.api.nvim_cmd({ cmd = "wincmd", args = { "h" } }, {})
    vim.api.nvim_cmd({ cmd = "wincmd", args = { "l" } }, {})
    local middle_win = vim.api.nvim_get_current_win()
    vim.api.nvim_cmd({ cmd = "wincmd", args = { "l" } }, {})
    local right_win = vim.api.nvim_get_current_win()

    vim.api.nvim_set_current_win(middle_win)
    local model = stack.push(location, { stack = false })
    assert.is_not_nil(model)
    vim.api.nvim_set_current_win(model.winid)

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-w>l", true, false, true), "x", false)
    assert.equals(right_win, vim.api.nvim_get_current_win())

    assert.is_true(stack.close(model.id))
    vim.api.nvim_cmd({ cmd = "only" }, {})
  end)

  it("should handle normal peek mode", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    peekstack.peek_location(location, {})

    -- The popup should be in the stack for normal mode
    local stack_list = stack.list()
    assert.equals(1, #stack_list)
  end)

  it("ignores invalid location payload safely", function()
    local original_notify = vim.notify
    local notifications = {}
    vim.notify = function(msg)
      table.insert(notifications, msg)
    end

    peekstack.peek_location({ uri = vim.uri_from_bufnr(0) }, {})

    vim.notify = original_notify
    assert.equals(0, #stack.list())
    assert.is_true(#notifications > 0)
    assert.is_true(tostring(notifications[1]):find("Invalid location payload", 1, true) ~= nil)
  end)
end)
