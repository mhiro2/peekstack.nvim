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
end)
