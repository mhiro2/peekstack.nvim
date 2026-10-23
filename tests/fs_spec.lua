local fs = require("peekstack.util.fs")

---Build two sibling repositories (one with a subdirectory) and a plain
---directory outside any repository, all under a fresh temp root.
---cleanup() restores the original cwd and removes the tree.
local function make_repo_fixture()
  local original_cwd = vim.fn.getcwd()
  -- Resolve symlinks (e.g. /var -> /private/var) so paths match getcwd().
  local root = vim.fn.resolve(vim.fn.tempname())
  local fixture = {
    repo = root .. "/repo",
    repo_sub = root .. "/repo/src/nested",
    other_repo = root .. "/other",
    plain = root .. "/plain",
  }
  vim.fn.mkdir(fixture.repo .. "/.git", "p")
  vim.fn.mkdir(fixture.repo_sub, "p")
  vim.fn.mkdir(fixture.other_repo .. "/.git", "p")
  vim.fn.mkdir(fixture.plain, "p")

  function fixture.cleanup()
    vim.api.nvim_set_current_dir(original_cwd)
    vim.fn.delete(root, "rf")
  end

  return fixture
end

describe("fs", function()
  describe("slug", function()
    it("returns 'default' for nil input", function()
      assert.equals("default", fs.slug(nil))
    end)

    it("returns 'default' for empty string", function()
      assert.equals("default", fs.slug(""))
    end)

    it("returns the sha256 hex digest of the input", function()
      assert.equals("9dad1e4e08b0b11cbcd860257e8bdfa6b8e5f01790e10a6a0b1f4870c13e686b", fs.slug("/home/user/project"))
      assert.equals("ae1608896372720b6ebb58261e0c0092c608324b0804bc99267c1753990faaa8", fs.slug("test-input"))
    end)

    it("falls back to a filename-safe slug when sha256 is unavailable", function()
      local original_sha256 = vim.fn.sha256
      vim.fn.sha256 = function()
        error("sha256 unavailable")
      end

      local ok, result = pcall(fs.slug, "/home/user/my project:v1.2-x_y")
      vim.fn.sha256 = original_sha256

      assert.is_true(ok, tostring(result))
      assert.equals("_home_user_my_project_v1.2-x_y", result)
    end)
  end)

  describe("win_is_valid", function()
    it("returns false for nil input", function()
      assert.is_false(fs.win_is_valid(nil))
    end)

    it("returns true for current window", function()
      assert.is_true(fs.win_is_valid(vim.api.nvim_get_current_win()))
    end)

    it("returns false for closed window", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local winid = vim.api.nvim_open_win(bufnr, false, {
        relative = "editor",
        row = 0,
        col = 0,
        width = 1,
        height = 1,
        style = "minimal",
      })

      assert.is_true(fs.win_is_valid(winid))
      vim.api.nvim_win_close(winid, true)
      assert.is_false(fs.win_is_valid(winid))

      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)
  end)

  describe("buf_is_valid", function()
    it("returns false for nil input", function()
      assert.is_false(fs.buf_is_valid(nil))
    end)

    it("returns true for current buffer", function()
      assert.is_true(fs.buf_is_valid(vim.api.nvim_get_current_buf()))
    end)

    it("returns false for deleted buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      assert.is_true(fs.buf_is_valid(bufnr))

      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.is_false(fs.buf_is_valid(bufnr))
    end)
  end)

  describe("ensure_dir", function()
    it("is idempotent for an existing directory", function()
      local dir = vim.fn.tempname()
      assert.equals(dir, fs.ensure_dir(dir))
      assert.equals(1, vim.fn.isdirectory(dir))
      assert.equals(dir, fs.ensure_dir(dir))
      assert.equals(1, vim.fn.isdirectory(dir))

      vim.fn.delete(dir, "rf")
    end)

    it("tolerates a concurrent mkdir losing the race", function()
      local dir = vim.fn.tempname()
      local original_mkdir = vim.fn.mkdir
      vim.fn.mkdir = function(path, flags)
        -- Emulate another process creating the directory first.
        original_mkdir(path, flags)
        error("Vim:E739: Cannot create directory " .. path .. ": file already exists")
      end

      local ok, result = pcall(fs.ensure_dir, dir)
      vim.fn.mkdir = original_mkdir

      assert.is_true(ok, tostring(result))
      assert.equals(dir, result)
      assert.equals(1, vim.fn.isdirectory(dir))

      vim.fn.delete(dir, "rf")
    end)

    it("retries when a concurrent mkdir aborts on an intermediate directory", function()
      local base = vim.fn.tempname()
      local dir = base .. "/nested/leaf"
      local original_mkdir = vim.fn.mkdir
      local calls = 0
      vim.fn.mkdir = function(path, flags)
        calls = calls + 1
        if calls == 1 then
          -- Another process created an intermediate component first, aborting
          -- this mkdir before the leaf directory exists.
          original_mkdir(base .. "/nested", flags)
          error("Vim:E739: Cannot create directory " .. base .. "/nested: file already exists")
        end
        return original_mkdir(path, flags)
      end

      local ok, result = pcall(fs.ensure_dir, dir)
      vim.fn.mkdir = original_mkdir

      assert.is_true(ok, tostring(result))
      assert.equals(dir, result)
      assert.equals(1, vim.fn.isdirectory(dir))
      assert.equals(2, calls)

      vim.fn.delete(base, "rf")
    end)

    it("propagates a genuine mkdir failure", function()
      local dir = vim.fn.tempname()
      local original_mkdir = vim.fn.mkdir
      vim.fn.mkdir = function()
        error("Vim:E739: Cannot create directory")
      end

      local ok = pcall(fs.ensure_dir, dir)
      vim.fn.mkdir = original_mkdir

      assert.is_false(ok)
      assert.equals(0, vim.fn.isdirectory(dir))
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

    describe("with a repository fixture", function()
      local fixture

      before_each(function()
        fixture = make_repo_fixture()
      end)

      after_each(function()
        fixture.cleanup()
      end)

      it("names the 'repo' scope after the repository root from a subdirectory", function()
        vim.api.nvim_set_current_dir(fixture.repo_sub)
        local base = vim.fn.stdpath("state") .. "/peekstack"

        assert.equals(base .. "/repo_" .. vim.fn.sha256(fixture.repo) .. ".json", fs.scope_path("repo"))
      end)

      it("gives another repository its own 'repo' scope path", function()
        vim.api.nvim_set_current_dir(fixture.other_repo)
        local base = vim.fn.stdpath("state") .. "/peekstack"

        assert.equals(base .. "/repo_" .. vim.fn.sha256(fixture.other_repo) .. ".json", fs.scope_path("repo"))
      end)

      it("falls back to the cwd path for 'repo' scope outside a repository", function()
        vim.api.nvim_set_current_dir(fixture.plain)
        local base = vim.fn.stdpath("state") .. "/peekstack"

        assert.equals(base .. "/cwd_" .. vim.fn.sha256(fixture.plain) .. ".json", fs.scope_path("repo"))
      end)
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

    it("finds the enclosing repository root from the current directory", function()
      local fixture = make_repo_fixture()
      local ok, err = pcall(function()
        vim.api.nvim_set_current_dir(fixture.repo_sub)
        assert.equals(fixture.repo, fs.repo_root())

        vim.api.nvim_set_current_dir(fixture.other_repo)
        assert.equals(fixture.other_repo, fs.repo_root())

        vim.api.nvim_set_current_dir(fixture.plain)
        assert.is_nil(fs.repo_root())
      end)
      fixture.cleanup()
      if not ok then
        error(err)
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
