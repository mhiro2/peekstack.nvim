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

  describe("existing buffer-local mappings with other spellings", function()
    local saved_leader
    local temp
    local script
    local source_bufnr
    local root_win

    --- Resolve a mapping the same way Neovim does. Lua callbacks are re-wrapped
    --- by maparg(), so only their presence is compared; behaviour is checked
    --- by assert_originals_work(). A `:map` entry may come back split per mode,
    --- so the combined mode spelling is ignored.
    ---@param lhs string
    ---@param mode string
    ---@return table
    local function resolve_mode(lhs, mode)
      local item = vim.api.nvim_buf_call(source_bufnr, function()
        return vim.fn.maparg(lhs, mode, false, true)
      end)
      item.lnum = nil
      item.callback = item.callback and true or nil
      item.mode = nil
      item.mode_bits = nil
      return item
    end

    ---@param lhs string
    ---@return table
    local function resolve(lhs)
      return resolve_mode(lhs, "n")
    end

    before_each(function()
      saved_leader = vim.g.mapleader
      vim.g.mapleader = ","
      temp = vim.fn.tempname() .. ".lua"
      vim.fn.writefile({ "print('peekstack')" }, temp)
      vim.api.nvim_cmd({ cmd = "edit", args = { temp } }, {})
      root_win = vim.api.nvim_get_current_win()
      source_bufnr = vim.api.nvim_get_current_buf()

      -- Mappings written with different spellings than peekstack's specs,
      -- including a script-local <SID> expr mapping and a Lua callback.
      script = vim.fn.tempname() .. ".vim"
      vim.fn.writefile({
        "function! s:Original() abort",
        "  let g:peekstack_original_sid = 1",
        "  return ''",
        "endfunction",
        "nnoremap <buffer> <expr> <C-J> <SID>Original()",
        "noremap <buffer> <silent> <Leader>os :let g:peekstack_original_leader = 1<CR>",
      }, script)
      vim.api.nvim_cmd({ cmd = "source", args = { script } }, {})
      vim.keymap.set("n", "<c-w>h", function()
        vim.g.peekstack_original_callback = 1
      end, { buffer = source_bufnr, desc = "Original window left" })
    end)

    after_each(function()
      vim.g.mapleader = saved_leader
      vim.g.peekstack_original_sid = nil
      vim.g.peekstack_original_leader = nil
      vim.g.peekstack_original_callback = nil
      vim.fn.delete(temp)
      vim.fn.delete(script)
    end)

    local function open_source_popup()
      local model = popup.create({
        uri = vim.uri_from_fname(temp),
        range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
        provider = "test",
      }, {
        buffer_mode = "source",
      })
      assert.is_not_nil(model)
      return model
    end

    ---@param keys string
    local function feed(keys)
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
    end

    local function assert_originals_work()
      vim.api.nvim_set_current_win(root_win)
      feed("<C-j>")
      feed("<leader>os")
      feed("<C-w>h")
      assert.equals(1, vim.g.peekstack_original_sid)
      assert.equals(1, vim.g.peekstack_original_leader)
      assert.equals(1, vim.g.peekstack_original_callback)
    end

    it("restores Ctrl, leader and <SID> mappings after popup close", function()
      local lhs_list = { "<C-j>", "<leader>os", "<C-w>h" }
      local before = vim.tbl_map(resolve, lhs_list)
      local visual_before = resolve_mode(",os", "x")
      local pending_before = resolve_mode(",os", "o")

      local model = open_source_popup()
      assert.equals("Peekstack focus next", resolve("<C-j>").desc)
      assert.equals("Peekstack stack view", resolve("<leader>os").desc)
      assert.equals("Peekstack navigate left", resolve("<C-w>h").desc)

      popup.close(model)

      for i, lhs in ipairs(lhs_list) do
        assert.same(before[i], resolve(lhs))
      end
      -- The `:noremap` mapping also keeps its visual/operator-pending modes.
      assert.same(visual_before, resolve_mode(",os", "x"))
      assert.same(pending_before, resolve_mode(",os", "o"))
      assert_originals_work()
    end)

    it("restores Ctrl, leader and <SID> mappings when leaving the popup", function()
      require("peekstack.core.events").setup()
      local model = open_source_popup()
      assert.equals(model.winid, vim.api.nvim_get_current_win())
      assert.equals("Peekstack focus next", resolve("<C-j>").desc)

      vim.api.nvim_set_current_win(root_win)

      assert.is_nil(resolve("<C-j>").desc)
      assert.equals("Original window left", resolve("<C-w>h").desc)
      assert_originals_work()

      popup.close(model)
    end)

    it("keeps other modes of a :map mapping changed while the popup is open", function()
      local model = open_source_popup()
      vim.keymap.set("x", ",os", "<Nop>", { buffer = source_bufnr, desc = "Updated visual" })
      vim.api.nvim_set_current_win(root_win)
      vim.api.nvim_cmd({ cmd = "enew" }, {})
      assert.is_not.equals(source_bufnr, vim.api.nvim_get_current_buf())

      popup.close(model)

      assert.equals("Updated visual", resolve_mode(",os", "x").desc)
      assert.equals(":let g:peekstack_original_leader = 1<CR>", resolve("<leader>os").rhs)
    end)

    it("cleans up leader mappings after mapleader changes", function()
      vim.keymap.set("n", ";os", "<Nop>", { buffer = source_bufnr, desc = "Unrelated" })
      local model = open_source_popup()
      vim.g.mapleader = ";"

      popup.close(model)

      assert.equals("Unrelated", resolve(";os").desc)
      assert.equals(":let g:peekstack_original_leader = 1<CR>", resolve(",os").rhs)
    end)

    it("does not turn global mappings into buffer-local ones", function()
      vim.keymap.del("n", "<C-j>", { buffer = source_bufnr })
      vim.keymap.set("n", "<C-J>", "<Nop>", { desc = "Global next" })

      local model = open_source_popup()
      popup.close(model)

      local item = resolve("<C-j>")
      assert.equals(0, item.buffer)
      assert.equals("Global next", item.desc)
      vim.keymap.del("n", "<C-J>")
    end)
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
