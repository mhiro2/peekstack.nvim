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
    local original_ensure_dir

    before_each(function()
      fs._reset_scope_path_cache()
      original_ensure_dir = fs.ensure_dir
    end)

    after_each(function()
      fs.ensure_dir = original_ensure_dir
      fs._reset_scope_path_cache()
    end)

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

    it("runs ensure_dir only once after cache warmup", function()
      local calls = 0
      fs.ensure_dir = function(path)
        calls = calls + 1
        return path
      end

      fs.scope_path("global")
      fs.scope_path("cwd")
      fs.scope_path("global")

      assert.equals(1, calls)
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
    local original_find

    before_each(function()
      fs._reset_repo_root_cache()
      original_find = vim.fs.find
    end)

    after_each(function()
      vim.fs.find = original_find
      fs._reset_repo_root_cache()
    end)

    it("finds repo root from current directory", function()
      local root = fs.repo_root()
      -- We're running in the plugin repo, so this should find a root
      if root then
        assert.is_string(root)
      end
    end)

    it("caches current-directory lookups", function()
      local calls = 0
      vim.fs.find = function(name, opts)
        calls = calls + 1
        assert.equals(".git", name)
        assert.is_truthy(opts)
        return { "/tmp/peekstack-cache/.git" }
      end

      assert.equals("/tmp/peekstack-cache", fs.repo_root())
      assert.equals("/tmp/peekstack-cache", fs.repo_root())
      assert.equals(1, calls)
    end)

    it("invalidates cache on DirChanged", function()
      local calls = 0
      vim.fs.find = function()
        calls = calls + 1
        if calls == 1 then
          return { "/tmp/peekstack-before/.git" }
        end
        return { "/tmp/peekstack-after/.git" }
      end

      assert.equals("/tmp/peekstack-before", fs.repo_root())
      assert.equals("/tmp/peekstack-before", fs.repo_root())
      assert.equals(1, calls)

      vim.api.nvim_exec_autocmds("DirChanged", { modeline = false })
      assert.equals("/tmp/peekstack-after", fs.repo_root())
      assert.equals(2, calls)
    end)

    it("does not cache explicit start paths", function()
      local calls = 0
      vim.fs.find = function(_, opts)
        calls = calls + 1
        if opts.path == "/tmp/a/project" then
          return { "/tmp/a/.git" }
        end
        return { "/tmp/b/.git" }
      end

      assert.equals("/tmp/a", fs.repo_root("/tmp/a/project"))
      assert.equals("/tmp/a", fs.repo_root("/tmp/a/project"))
      assert.equals(2, calls)
    end)
  end)
end)
