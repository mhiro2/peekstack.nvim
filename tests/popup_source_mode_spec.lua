describe("popup source mode", function()
  local popup = require("peekstack.core.popup")
  local config = require("peekstack.config")
  local stack = require("peekstack.core.stack")

  ---@param bufnr integer
  ---@param lhs string
  ---@return boolean
  local function has_buffer_map(bufnr, lhs)
    for _, item in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      if item.lhs == lhs then
        return true
      end
    end
    return false
  end

  ---@param bufnr integer
  ---@param lhs string
  ---@return vim.api.keyset.get_keymap?
  local function get_buffer_map(bufnr, lhs)
    for _, item in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      if item.lhs == lhs then
        return item
      end
    end
    return nil
  end

  before_each(function()
    popup._reset()
    stack._reset()
    config.setup({})
  end)

  after_each(function()
    stack._reset()
    popup._reset()
  end)

  local function make_location()
    return {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }
  end

  it("creates popup in copy mode by default", function()
    local loc = make_location()
    local model = popup.create(loc)
    assert.is_not_nil(model)
    assert.equals("copy", model.buffer_mode)
    assert.is_true(model.bufnr ~= model.source_bufnr)
    popup.close(model)
  end)

  it("creates popup in source mode when opts.buffer_mode is source", function()
    local loc = make_location()
    local model = popup.create(loc, { buffer_mode = "source" })
    assert.is_not_nil(model)
    assert.equals("source", model.buffer_mode)
    assert.equals(model.source_bufnr, model.bufnr)
    popup.close(model)
  end)

  it("creates popup in source mode when config default is source", function()
    config.setup({ ui = { popup = { buffer_mode = "source" } } })
    local loc = make_location()
    local model = popup.create(loc)
    assert.is_not_nil(model)
    assert.equals("source", model.buffer_mode)
    assert.equals(model.source_bufnr, model.bufnr)
    popup.close(model)
  end)

  it("opts.buffer_mode overrides config default", function()
    config.setup({ ui = { popup = { buffer_mode = "source" } } })
    local loc = make_location()
    local model = popup.create(loc, { buffer_mode = "copy" })
    assert.is_not_nil(model)
    assert.equals("copy", model.buffer_mode)
    assert.is_true(model.bufnr ~= model.source_bufnr)
    popup.close(model)
  end)

  it("source mode buffer is the real file buffer", function()
    local loc = make_location()
    local model = popup.create(loc, { buffer_mode = "source" })
    assert.is_not_nil(model)
    -- buftype should NOT be "nofile" for source mode
    assert.is_true(vim.bo[model.bufnr].buftype ~= "nofile")
    popup.close(model)
  end)

  it("keeps source mode buffers listed", function()
    local temp = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "print('peekstack')" }, temp)
    vim.api.nvim_cmd({ cmd = "edit", args = { temp } }, {})
    local source_bufnr = vim.api.nvim_get_current_buf()
    vim.bo[source_bufnr].buflisted = true
    local loc = {
      uri = vim.uri_from_fname(temp),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }
    local model = popup.create(loc, { buffer_mode = "source" })
    assert.is_not_nil(model)
    assert.equals(source_bufnr, model.bufnr)
    assert.is_true(vim.bo[model.bufnr].buflisted)
    popup.close(model)
  end)

  it("copy mode buffer is a scratch buffer", function()
    local loc = make_location()
    local model = popup.create(loc, { buffer_mode = "copy" })
    assert.is_not_nil(model)
    assert.equals("nofile", vim.bo[model.bufnr].buftype)
    assert.is_true(has_buffer_map(model.bufnr, config.get().ui.keys.close))
    popup.close(model)
  end)

  it("installs popup keymaps on source buffers and removes them on close", function()
    local temp = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "print('peekstack')" }, temp)
    vim.api.nvim_cmd({ cmd = "edit", args = { temp } }, {})
    local source_bufnr = vim.api.nvim_get_current_buf()
    local close_key = config.get().ui.keys.close

    assert.is_false(has_buffer_map(source_bufnr, close_key))

    local model = popup.create({
      uri = vim.uri_from_fname(temp),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }, {
      buffer_mode = "source",
    })

    assert.is_not_nil(model)
    -- Keymaps are installed while popup is open
    assert.is_true(has_buffer_map(source_bufnr, close_key))

    popup.close(model)
    -- Keymaps are removed after popup close
    assert.is_false(has_buffer_map(source_bufnr, close_key))

    vim.fn.delete(temp)
  end)

  it("restores existing source buffer keymaps after popup close", function()
    local temp = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "print('peekstack')" }, temp)
    vim.api.nvim_cmd({ cmd = "edit", args = { temp } }, {})
    local source_bufnr = vim.api.nvim_get_current_buf()
    local close_key = config.get().ui.keys.close

    vim.keymap.set("n", close_key, function() end, {
      buffer = source_bufnr,
      desc = "Original buffer close",
    })

    local model = popup.create({
      uri = vim.uri_from_fname(temp),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }, {
      buffer_mode = "source",
    })

    assert.is_not_nil(model)
    assert.equals("Peekstack close", get_buffer_map(source_bufnr, close_key).desc)

    popup.close(model)

    local restored = get_buffer_map(source_bufnr, close_key)
    assert.is_not_nil(restored)
    assert.equals("Original buffer close", restored.desc)

    vim.fn.delete(temp)
  end)

  it("restores source buffer keymaps when leaving a source popup", function()
    require("peekstack.core.events").setup()
    local temp = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "print('peekstack')" }, temp)
    vim.api.nvim_cmd({ cmd = "edit", args = { temp } }, {})
    local root_win = vim.api.nvim_get_current_win()
    local source_bufnr = vim.api.nvim_get_current_buf()
    local close_key = config.get().ui.keys.close

    vim.keymap.set("n", close_key, function() end, {
      buffer = source_bufnr,
      desc = "Original buffer close",
    })

    local model = popup.create({
      uri = vim.uri_from_fname(temp),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }, {
      buffer_mode = "source",
    })

    assert.is_not_nil(model)
    assert.equals("Peekstack close", get_buffer_map(source_bufnr, close_key).desc)

    vim.api.nvim_set_current_win(root_win)

    local restored = get_buffer_map(source_bufnr, close_key)
    assert.is_not_nil(restored)
    assert.equals("Original buffer close", restored.desc)

    popup.close(model)
    vim.fn.delete(temp)
  end)

  it("installs <C-w>hjkl navigation keymaps on copy-mode popups", function()
    local loc = make_location()
    local model = popup.create(loc, { buffer_mode = "copy" })
    assert.is_not_nil(model)
    assert.is_true(has_buffer_map(model.bufnr, "<C-W>h"))
    assert.is_true(has_buffer_map(model.bufnr, "<C-W>j"))
    assert.is_true(has_buffer_map(model.bufnr, "<C-W>k"))
    assert.is_true(has_buffer_map(model.bufnr, "<C-W>l"))
    popup.close(model)
  end)

  it("<C-w>l navigates from popup to adjacent split", function()
    -- Create a vertical split so there are two windows.
    vim.api.nvim_cmd({ cmd = "vsplit" }, {})
    local left_win = vim.api.nvim_get_current_win()
    -- Move to the right split.
    vim.api.nvim_cmd({ cmd = "wincmd", args = { "l" } }, {})
    local right_win = vim.api.nvim_get_current_win()
    assert.is_not.equals(left_win, right_win)

    -- Open a popup anchored to the right split.
    local loc = make_location()
    local model = stack.push(loc)
    assert.is_not_nil(model)
    -- Focus the popup (simulates user entering the floating window).
    vim.api.nvim_set_current_win(model.winid)
    assert.equals(model.winid, vim.api.nvim_get_current_win())

    -- Execute the <C-w>h keymap callback: should land on the left split.
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-w>h", true, false, true), "x", false)
    assert.equals(left_win, vim.api.nvim_get_current_win())

    -- Cleanup
    stack.close(model.id)
    vim.api.nvim_set_current_win(right_win)
    vim.api.nvim_cmd({ cmd = "close" }, {})
  end)

  it("installs <C-w>hjkl keymaps on source-mode popups and removes them on close", function()
    local temp = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "print('peekstack')" }, temp)
    vim.api.nvim_cmd({ cmd = "edit", args = { temp } }, {})
    local source_bufnr = vim.api.nvim_get_current_buf()

    local model = popup.create({
      uri = vim.uri_from_fname(temp),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }, {
      buffer_mode = "source",
    })

    assert.is_not_nil(model)
    -- Keymaps are installed while popup is open
    assert.is_true(has_buffer_map(source_bufnr, "<C-W>h"))
    assert.is_true(has_buffer_map(source_bufnr, "<C-W>j"))
    assert.is_true(has_buffer_map(source_bufnr, "<C-W>k"))
    assert.is_true(has_buffer_map(source_bufnr, "<C-W>l"))

    popup.close(model)
    -- Keymaps are removed after popup close
    assert.is_false(has_buffer_map(source_bufnr, "<C-W>h"))
    assert.is_false(has_buffer_map(source_bufnr, "<C-W>j"))
    assert.is_false(has_buffer_map(source_bufnr, "<C-W>k"))
    assert.is_false(has_buffer_map(source_bufnr, "<C-W>l"))

    vim.fn.delete(temp)
  end)

  it("routes source-mode keymaps to the focused popup when multiple popups share a buffer", function()
    local temp = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "print('peekstack')" }, temp)
    vim.api.nvim_cmd({ cmd = "edit", args = { temp } }, {})
    local loc = {
      uri = vim.uri_from_fname(temp),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }

    local first = stack.push(loc, { buffer_mode = "source" })
    local second = stack.push(loc, { buffer_mode = "source" })
    assert.is_not_nil(first)
    assert.is_not_nil(second)

    vim.api.nvim_set_current_win(first.winid)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(config.get().ui.keys.close, true, false, true), "x", false)

    assert.is_false(vim.api.nvim_win_is_valid(first.winid))
    assert.is_true(vim.api.nvim_win_is_valid(second.winid))

    vim.api.nvim_set_current_win(second.winid)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(config.get().ui.keys.close, true, false, true), "x", false)

    assert.is_false(vim.api.nvim_win_is_valid(second.winid))

    vim.fn.delete(temp)
  end)

  it("keeps the remaining source popup focused when the active one closes", function()
    local temp = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "print('peekstack')" }, temp)
    vim.api.nvim_cmd({ cmd = "edit", args = { temp } }, {})
    local source_bufnr = vim.api.nvim_get_current_buf()
    local close_key = config.get().ui.keys.close
    local loc = {
      uri = vim.uri_from_fname(temp),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      provider = "test",
    }

    local first = stack.push(loc, { buffer_mode = "source" })
    local second = stack.push(loc, { buffer_mode = "source" })
    assert.is_not_nil(first)
    assert.is_not_nil(second)
    assert.equals(second.winid, vim.api.nvim_get_current_win())
    assert.equals("Peekstack close", get_buffer_map(source_bufnr, close_key).desc)

    stack.close(second.id)

    assert.is_false(vim.api.nvim_win_is_valid(second.winid))
    assert.is_true(vim.api.nvim_win_is_valid(first.winid))
    assert.equals(first.winid, vim.api.nvim_get_current_win())
    assert.equals("Peekstack close", get_buffer_map(source_bufnr, close_key).desc)

    stack.close(first.id)
    vim.fn.delete(temp)
  end)

  it("deletes copy-mode scratch buffer when render.open fails", function()
    local render = require("peekstack.ui.render")
    local loc = make_location()
    local original_open = render.open
    local created_bufnr = nil

    local ok, err = pcall(function()
      render.open = function(bufnr)
        created_bufnr = bufnr
        error("open failed")
      end
      local model = popup.create(loc, { buffer_mode = "copy" })
      assert.is_nil(model)
    end)

    render.open = original_open
    if not ok then
      error(err)
    end

    assert.is_not_nil(created_bufnr)
    assert.is_false(vim.api.nvim_buf_is_valid(created_bufnr))
  end)
end)
