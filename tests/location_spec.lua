local location = require("peekstack.core.location")

describe("location", function()
  describe("normalize", function()
    it("returns nil for nil input", function()
      assert.is_nil(location.normalize(nil))
    end)

    it("normalizes an LSP location with uri and range", function()
      local loc = {
        uri = "file:///tmp/foo.lua",
        range = {
          start = { line = 10, character = 5 },
          ["end"] = { line = 10, character = 15 },
        },
      }
      local result = location.normalize(loc, "lsp.definition")
      assert.is_not_nil(result)
      assert.equals("file:///tmp/foo.lua", result.uri)
      assert.equals(10, result.range.start.line)
      assert.equals(5, result.range.start.character)
      assert.equals("lsp.definition", result.provider)
    end)

    it("normalizes a targetUri/targetRange location", function()
      local loc = {
        targetUri = "file:///tmp/bar.lua",
        targetRange = {
          start = { line = 3, character = 0 },
          ["end"] = { line = 3, character = 10 },
        },
      }
      local result = location.normalize(loc, "lsp.definition")
      assert.is_not_nil(result)
      assert.equals("file:///tmp/bar.lua", result.uri)
      assert.equals(3, result.range.start.line)
    end)

    it("normalizes a filename-based location", function()
      local loc = {
        filename = "/tmp/test.lua",
        lnum = 5,
        col = 3,
        text = "hello",
      }
      local result = location.normalize(loc, "grep.rg")
      assert.is_not_nil(result)
      assert.is_true(result.uri:find("test.lua") ~= nil)
      assert.equals(4, result.range.start.line) -- lnum 5 -> line 4 (0-indexed)
      assert.equals(2, result.range.start.character) -- col 3 -> character 2 (0-indexed)
      assert.equals("hello", result.text)
      assert.equals("grep.rg", result.provider)
    end)

    it("returns nil for unknown location format", function()
      local loc = { unknown = "data" }
      assert.is_nil(location.normalize(loc, "test"))
    end)

    it("returns nil for a location with uri but no range", function()
      local loc = { uri = "file:///tmp/foo.lua" }
      local result = location.normalize(loc, "test")
      -- from_lsp_location requires both uri and range
      assert.is_nil(result)
    end)

    it("preserves text and kind fields", function()
      local loc = {
        uri = "file:///tmp/foo.lua",
        range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
        text = "error message",
        kind = 1,
      }
      local result = location.normalize(loc, "diagnostics")
      assert.equals("error message", result.text)
      assert.equals(1, result.kind)
    end)

    it("defaults lnum and col for filename-based location", function()
      local loc = { filename = "/tmp/test.lua" }
      local result = location.normalize(loc, "test")
      assert.is_not_nil(result)
      assert.equals(0, result.range.start.line)
      assert.equals(0, result.range.start.character)
    end)
  end)

  describe("list_from_lsp", function()
    it("returns empty table for nil result", function()
      local items = location.list_from_lsp(nil, "lsp.definition")
      assert.same({}, items)
    end)

    it("handles a single LSP location (not a list)", function()
      local result = {
        uri = "file:///tmp/single.lua",
        range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 5 } },
      }
      local items = location.list_from_lsp(result, "lsp.definition")
      assert.equals(1, #items)
      assert.equals("file:///tmp/single.lua", items[1].uri)
    end)

    it("handles a list of LSP locations", function()
      local result = {
        {
          uri = "file:///tmp/a.lua",
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
        },
        {
          uri = "file:///tmp/b.lua",
          range = { start = { line = 5, character = 2 }, ["end"] = { line = 5, character = 10 } },
        },
      }
      local items = location.list_from_lsp(result, "lsp.refs")
      assert.equals(2, #items)
      assert.equals("file:///tmp/a.lua", items[1].uri)
      assert.equals("file:///tmp/b.lua", items[2].uri)
      assert.equals("lsp.refs", items[1].provider)
    end)

    it("skips invalid entries in a list", function()
      local result = {
        {
          uri = "file:///tmp/valid.lua",
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
        },
        { invalid = true },
        nil,
      }
      local items = location.list_from_lsp(result, "test")
      assert.equals(1, #items)
    end)
  end)

  describe("display_text", function()
    it("formats location as path:line:col", function()
      local cwd = vim.fn.getcwd()
      local loc = {
        uri = vim.uri_from_fname(cwd .. "/lua/init.lua"),
        range = { start = { line = 9, character = 4 }, ["end"] = { line = 9, character = 10 } },
      }
      local text = location.display_text(loc, 0)
      assert.is_true(text:find("10:5") ~= nil)
    end)

    it("includes text when preview_lines > 0", function()
      local loc = {
        uri = "file:///tmp/test.lua",
        range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
        text = "some preview text",
      }
      local text = location.display_text(loc, 1)
      assert.is_true(text:find("some preview text") ~= nil)
    end)

    it("excludes text when preview_lines is 0", function()
      local loc = {
        uri = "file:///tmp/test.lua",
        range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
        text = "some preview text",
      }
      local text = location.display_text(loc, 0)
      assert.is_nil(text:find("some preview text"))
    end)

    it("supports path options and truncation", function()
      local tmpdir = string.format("%s/peekstack-%d", vim.uv.os_tmpdir(), vim.uv.hrtime())
      local repo = tmpdir .. "/repo"
      local subdir = repo .. "/subdir"

      assert(vim.uv.fs_mkdir(tmpdir, 448))
      assert(vim.uv.fs_mkdir(repo, 448))
      assert(vim.uv.fs_mkdir(repo .. "/.git", 448))
      assert(vim.uv.fs_mkdir(subdir, 448))

      local path = subdir .. "/very_long_filename.lua"
      local loc = {
        uri = vim.uri_from_fname(path),
        range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      }

      local text = location.display_text(loc, 0, { path_base = "repo", max_width = 12 })
      assert.is_true(text:find(":1:1", 1, true) ~= nil)
      assert.is_true(text:find("...", 1, true) ~= nil)
      assert.is_nil(text:find(tmpdir, 1, true))

      assert(vim.uv.fs_rmdir(subdir))
      assert(vim.uv.fs_rmdir(repo .. "/.git"))
      assert(vim.uv.fs_rmdir(repo))
      assert(vim.uv.fs_rmdir(tmpdir))
    end)
  end)
end)
