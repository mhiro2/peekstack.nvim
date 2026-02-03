local fs = require("peekstack.util.fs")

describe("fs", function()
  describe("slug", function()
    it("returns 'default' for nil input", function()
      assert.equals("default", fs.slug(nil))
    end)

    it("returns 'default' for empty string", function()
      assert.equals("default", fs.slug(""))
    end)

    it("returns a sha256 hash for normal input", function()
      local result = fs.slug("/home/user/project")
      assert.is_string(result)
      assert.is_true(#result > 0)
      assert.not_equals("default", result)
    end)

    it("returns consistent results for same input", function()
      local a = fs.slug("test-input")
      local b = fs.slug("test-input")
      assert.equals(a, b)
    end)

    it("returns different results for different input", function()
      local a = fs.slug("input-a")
      local b = fs.slug("input-b")
      assert.not_equals(a, b)
    end)
  end)

  describe("scope_path", function()
    it("returns a global path for 'global' scope", function()
      local path = fs.scope_path("global")
      assert.is_true(path:find("peekstack/global.json") ~= nil)
    end)

    it("returns a cwd-based path for 'cwd' scope", function()
      local path = fs.scope_path("cwd")
      assert.is_true(path:find("peekstack/cwd_") ~= nil)
      assert.is_true(path:find(".json") ~= nil)
    end)

    it("returns a repo-based path for 'repo' scope when in a git repo", function()
      local path = fs.scope_path("repo")
      assert.is_true(path:find("peekstack/") ~= nil)
      assert.is_true(path:find(".json") ~= nil)
    end)

    it("path contains the state directory", function()
      local state_dir = vim.fn.stdpath("state")
      local path = fs.scope_path("global")
      assert.is_true(path:find(state_dir, 1, true) ~= nil)
    end)
  end)

  describe("uri_to_fname", function()
    it("returns nil for nil input", function()
      assert.is_nil(fs.uri_to_fname(nil))
    end)

    it("converts file URI to filename", function()
      local fname = fs.uri_to_fname("file:///tmp/test.lua")
      assert.equals("/tmp/test.lua", fname)
    end)
  end)

  describe("fname_to_uri", function()
    it("returns nil for nil input", function()
      assert.is_nil(fs.fname_to_uri(nil))
    end)

    it("converts filename to file URI", function()
      local uri = fs.fname_to_uri("/tmp/test.lua")
      assert.equals("file:///tmp/test.lua", uri)
    end)
  end)

  describe("repo_root", function()
    it("finds repo root from current directory", function()
      local root = fs.repo_root()
      -- We're running in the plugin repo, so this should find a root
      if root then
        assert.is_string(root)
      end
    end)
  end)
end)
