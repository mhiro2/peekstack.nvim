local str = require("peekstack.util.str")

describe("str.shorten_path", function()
  it("updates cached cwd after DirChanged", function()
    local original = vim.fn.getcwd()
    local tmpdir = string.format("%s/peekstack-%d", vim.uv.os_tmpdir(), vim.uv.hrtime())
    local ok, err = vim.uv.fs_mkdir(tmpdir, 448)
    if not ok and err then
      error(err)
    end

    vim.api.nvim_set_current_dir(tmpdir)
    local cwd = vim.fn.getcwd()
    local path = cwd .. "/file.txt"
    assert.equals("file.txt", str.shorten_path(path))

    vim.api.nvim_set_current_dir(original)
    assert.equals(path, str.shorten_path(path))

    vim.uv.fs_rmdir(tmpdir)
  end)
end)

describe("str.relative_path", function()
  it("uses repo root when available", function()
    local tmpdir = string.format("%s/peekstack-%d", vim.uv.os_tmpdir(), vim.uv.hrtime())
    local repo = tmpdir .. "/repo"
    local subdir = repo .. "/sub"

    assert(vim.uv.fs_mkdir(tmpdir, 448))
    assert(vim.uv.fs_mkdir(repo, 448))
    assert(vim.uv.fs_mkdir(repo .. "/.git", 448))
    assert(vim.uv.fs_mkdir(subdir, 448))

    local path = subdir .. "/file.lua"
    assert.equals("sub/file.lua", str.relative_path(path, "repo"))

    assert(vim.uv.fs_rmdir(subdir))
    assert(vim.uv.fs_rmdir(repo .. "/.git"))
    assert(vim.uv.fs_rmdir(repo))
    assert(vim.uv.fs_rmdir(tmpdir))
  end)

  it("reuses repo root lookups when cache is provided", function()
    local fs = require("peekstack.util.fs")
    local original_repo_root = fs.repo_root
    local repo_calls = 0
    local cache = {}
    local ok, err = pcall(function()
      fs.repo_root = function(start)
        repo_calls = repo_calls + 1
        assert.equals("/tmp/repo/src", start)
        return "/tmp/repo"
      end

      local opts = { repo_root_cache = cache }
      assert.equals("src/a.lua", str.relative_path("/tmp/repo/src/a.lua", "repo", opts))
      assert.equals("src/b.lua", str.relative_path("/tmp/repo/src/b.lua", "repo", opts))
      assert.equals(1, repo_calls)
    end)
    fs.repo_root = original_repo_root
    if not ok then
      error(err)
    end
  end)
end)

describe("str.truncate_middle", function()
  it("keeps both ends of long text around the ellipsis", function()
    -- 7 cells remain after the ellipsis: 4 from the start, 3 from the end.
    assert.equals("path...lua", str.truncate_middle("path/to/very/long/file.lua", 10))
    assert.equals("pat...ua", str.truncate_middle("path/to/very/long/file.lua", 8))
  end)

  it("returns text that already fits unchanged", function()
    assert.equals("file.lua", str.truncate_middle("file.lua", 8))
    assert.equals("file.lua", str.truncate_middle("file.lua", 20))
  end)

  it("returns only as much of the ellipsis as fits in tiny widths", function()
    local text = "path/to/very/long/file.lua"
    assert.equals("", str.truncate_middle(text, 0))
    assert.equals("", str.truncate_middle(text, -1))
    assert.equals(".", str.truncate_middle(text, 1))
    assert.equals("..", str.truncate_middle(text, 2))
    assert.equals("...", str.truncate_middle(text, 3))
    assert.equals("p...", str.truncate_middle(text, 4))
  end)

  it("cuts multibyte text on character boundaries", function()
    assert.equals("äb...öp", str.truncate_middle("äbcdefghijklmnöp", 7))
  end)

  it("returns an empty string for nil", function()
    assert.equals("", str.truncate_middle(nil, 10))
  end)
end)
