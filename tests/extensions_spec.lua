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

    it("actions.push takes the picker opts and the push opts separately", function()
      fzf_ext.actions.push({ "src/a.lua:2:3:text" }, { cwd = "/picker/root" }, { provider = "my_grep" })

      assert.equals(1, #captured)
      assert.equals(vim.uri_from_fname("/picker/root/src/a.lua"), captured[1].loc.uri)
      assert.equals("my_grep", captured[1].loc.provider)
    end)
  end)
end)
