describe("peekstack.extensions", function()
  local extensions = require("peekstack.extensions")
  local location = require("peekstack.core.location")

  describe("push_entry", function()
    it("converts filename entry to PeekstackLocation via location.normalize", function()
      local loc = location.normalize({
        filename = "/tmp/test.lua",
        lnum = 10,
        col = 5,
      }, "extension")
      assert.is_not_nil(loc)
      assert.is_true(loc.uri:find("test.lua") ~= nil)
      assert.equals(9, loc.range.start.line) -- 10 -> 9 (0-indexed)
      assert.equals(4, loc.range.start.character) -- 5 -> 4 (0-indexed)
      assert.equals("extension", loc.provider)
    end)

    it("defaults lnum and col to 1", function()
      local loc = location.normalize({
        filename = "/tmp/test.lua",
      }, "extension")
      assert.is_not_nil(loc)
      assert.equals(0, loc.range.start.line)
      assert.equals(0, loc.range.start.character)
    end)

    it("does nothing when entry is nil", function()
      -- Should not error
      extensions.push_entry(nil)
    end)

    it("does nothing when entry has no filename", function()
      -- Should not error
      extensions.push_entry({})
    end)

    it("uses provider from opts", function()
      local loc = location.normalize({
        filename = "/tmp/test.lua",
        lnum = 1,
        col = 1,
      }, "extension.file")
      assert.is_not_nil(loc)
      assert.equals("extension.file", loc.provider)
    end)
  end)

  describe("snacks actions.push", function()
    local snacks_ext = require("peekstack.extensions.snacks")
    local captured_loc
    local original_peek

    before_each(function()
      captured_loc = nil
      original_peek = require("peekstack").peek_location
      require("peekstack").peek_location = function(loc)
        captured_loc = loc
      end
    end)

    after_each(function()
      require("peekstack").peek_location = original_peek
    end)

    local function mock_picker()
      return { close = function() end }
    end

    it("converts snacks 0-based col to 1-based for location.normalize", function()
      snacks_ext.actions.push(mock_picker(), {
        file = "/tmp/test.lua",
        pos = { 10, 5 }, -- line=10 (1-based), col=5 (0-based)
      })
      assert.is_not_nil(captured_loc)
      assert.equals(9, captured_loc.range.start.line) -- 10 -> 9
      assert.equals(5, captured_loc.range.start.character) -- 0-based 5 -> 1-based 6 -> normalize -1 = 5
    end)

    it("handles first column (col=0) without going negative", function()
      snacks_ext.actions.push(mock_picker(), {
        file = "/tmp/test.lua",
        pos = { 1, 0 }, -- first line, first col (0-based)
      })
      assert.is_not_nil(captured_loc)
      assert.equals(0, captured_loc.range.start.line)
      assert.equals(0, captured_loc.range.start.character) -- 0-based 0 -> 1-based 1 -> normalize -1 = 0
    end)

    it("resolves relative file path using item.cwd", function()
      snacks_ext.actions.push(mock_picker(), {
        file = "src/main.lua",
        cwd = "/home/user/project",
        pos = { 1, 0 },
      })
      assert.is_not_nil(captured_loc)
      assert.is_true(captured_loc.uri:find("/home/user/project/src/main.lua") ~= nil)
    end)

    it("does not modify absolute file path even when cwd is present", function()
      snacks_ext.actions.push(mock_picker(), {
        file = "/absolute/path.lua",
        cwd = "/home/user/project",
        pos = { 1, 0 },
      })
      assert.is_not_nil(captured_loc)
      assert.is_true(captured_loc.uri:find("/absolute/path.lua") ~= nil)
      assert.is_nil(captured_loc.uri:find("/home/user/project"))
    end)

    it("does nothing when item is nil", function()
      snacks_ext.actions.push(mock_picker(), nil)
      assert.is_nil(captured_loc)
    end)
  end)

  describe("fzf-lua", function()
    local fzf_ext = require("peekstack.extensions.fzf_lua")
    local captured
    local fzf_calls
    local original_peek
    local original_fzf

    -- Mirrors fzf-lua's path.entry_to_file: relative entries are joined with the picker cwd.
    local function entry_to_file(entry, opts)
      opts = opts or {}
      local path, line, col = entry:match("^(.-):(%d+):(%d+)")
      path = path or entry
      if opts.cwd and path:sub(1, 1) ~= "/" then
        path = opts.cwd .. "/" .. path
      end
      return { path = path, line = tonumber(line) or 0, col = tonumber(col) or 0 }
    end

    local function picker(name)
      return function(opts)
        table.insert(fzf_calls, { name = name, opts = opts })
      end
    end

    before_each(function()
      captured = {}
      fzf_calls = {}
      original_peek = require("peekstack").peek_location
      require("peekstack").peek_location = function(loc, opts)
        table.insert(captured, { loc = loc, opts = opts })
      end
      original_fzf = package.loaded["fzf-lua"]
      package.loaded["fzf-lua"] = {
        path = { entry_to_file = entry_to_file },
        files = picker("files"),
        live_grep = picker("live_grep"),
        lsp_references = picker("lsp_references"),
      }
    end)

    after_each(function()
      require("peekstack").peek_location = original_peek
      package.loaded["fzf-lua"] = original_fzf
    end)

    ---Simulate fzf-lua confirming `line`: actions receive the picker opts.
    local function confirm(call, line)
      call.opts.actions["default"]({ line }, call.opts)
    end

    for _, case in ipairs({
      { fn = "push_file", entry = "same.lua", line = 0, col = 0 },
      { fn = "push_grep", entry = "same.lua:3:5:text", line = 2, col = 4 },
      { fn = "push_lsp_references", entry = "same.lua:7:2:text", line = 6, col = 1 },
    }) do
      it(case.fn .. " resolves entries against the picker cwd", function()
        fzf_ext[case.fn]({ cwd = "/picker/root", mode = "copy" })
        assert.equals(1, #fzf_calls)
        assert.is_nil(fzf_calls[1].opts.mode)

        confirm(fzf_calls[1], case.entry)

        assert.equals(1, #captured)
        assert.equals(vim.uri_from_fname("/picker/root/same.lua"), captured[1].loc.uri)
        assert.equals(case.line, captured[1].loc.range.start.line)
        assert.equals(case.col, captured[1].loc.range.start.character)
        assert.equals("copy", captured[1].opts.mode)
      end)
    end

    it("keeps the caller's actions and replaces only the confirm action", function()
      local user_default = function() end
      local send_to_qf = function() end
      fzf_ext.push_grep({ actions = { ["default"] = user_default, ["ctrl-q"] = send_to_qf } })

      local actions = fzf_calls[1].opts.actions
      assert.equals(send_to_qf, actions["ctrl-q"])
      assert.is_function(actions["default"])
      assert.are_not.equal(user_default, actions["default"])
    end)

    it("merges the confirm action into actions given as a function", function()
      local send_to_qf = function() end
      fzf_ext.push_grep({
        actions = function()
          return { ["ctrl-q"] = send_to_qf }
        end,
      })

      local actions = fzf_calls[1].opts.actions({})
      assert.equals(send_to_qf, actions["ctrl-q"])
      assert.is_function(actions["default"])
    end)

    it("actions.push takes the picker opts and the push opts separately", function()
      fzf_ext.actions.push({ "src/a.lua:2:3:text" }, { cwd = "/picker/root" }, { provider = "my_grep" })

      assert.equals(1, #captured)
      assert.equals(vim.uri_from_fname("/picker/root/src/a.lua"), captured[1].loc.uri)
      assert.equals("my_grep", captured[1].loc.provider)
    end)
  end)

  describe("telescope", function()
    local saved = {}
    local captured
    local builtin_calls

    local function stub(name, mod)
      saved[name] = package.loaded[name]
      package.loaded[name] = mod
    end

    before_each(function()
      captured = {}
      builtin_calls = {}
      stub(
        "peekstack",
        vim.tbl_extend("force", require("peekstack"), {
          peek_location = function(loc, opts)
            table.insert(captured, { loc = loc, opts = opts })
          end,
        })
      )
      stub("telescope", {
        register_extension = function(ext)
          return ext
        end,
      })
      stub("telescope.builtin", {
        live_grep = function(opts)
          table.insert(builtin_calls, opts)
        end,
      })
      stub("telescope.actions", { close = function() end })
      stub("telescope.actions.state", {
        get_selected_entry = function()
          return { filename = "/tmp/a.lua", lnum = 3, col = 2 }
        end,
      })
      stub("telescope._extensions.peekstack", nil)
    end)

    after_each(function()
      for name, mod in pairs(saved) do
        package.loaded[name] = mod
      end
      saved = {}
    end)

    ---@return table<string, function>, any
    local function attach(opts)
      local ext = require("telescope._extensions.peekstack")
      ext.exports.push_grep(opts)
      assert.equals(1, #builtin_calls)
      local maps = {}
      local result = builtin_calls[1].attach_mappings(42, function(mode, lhs, fn)
        maps[mode .. lhs] = fn
      end)
      return maps, result
    end

    it("pushes the selection on <CR> in insert and normal mode", function()
      local maps, result = attach({ mode = "copy" })
      assert.is_true(result)
      assert.is_nil(builtin_calls[1].mode)

      maps["i<CR>"](42)
      maps["n<CR>"](42)

      assert.equals(2, #captured)
      assert.equals("extension.grep", captured[1].loc.provider)
      assert.equals("copy", captured[1].opts.mode)
    end)

    it("runs the caller's attach_mappings after its own <CR> mapping", function()
      local user_fn = function() end
      local received_bufnr
      local maps, result = attach({
        attach_mappings = function(prompt_bufnr, map)
          received_bufnr = prompt_bufnr
          map("i", "<C-q>", user_fn)
          return false
        end,
      })

      assert.equals(42, received_bufnr)
      assert.is_false(result)
      assert.equals(user_fn, maps["i<C-q>"])
      assert.is_function(maps["i<CR>"])
    end)
  end)
end)
