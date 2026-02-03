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
end)

describe("str.truncate_middle", function()
  it("truncates long text with ellipsis within width", function()
    local text = "path/to/very/long/file.lua"
    local truncated = str.truncate_middle(text, 10)
    assert.is_true(truncated:find("...", 1, true) ~= nil)
    assert.is_true(vim.fn.strdisplaywidth(truncated) <= 10)
  end)
end)
