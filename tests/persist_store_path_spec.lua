describe("peekstack.persist store path", function()
  local persist = require("peekstack.persist")
  local config = require("peekstack.config")
  local fs = require("peekstack.util.fs")
  local store = require("peekstack.persist.store")
  local stack = require("peekstack.core.stack")

  local wait_timeout_ms = 1000
  local wait_interval_ms = 10

  local original_cwd = nil
  local work_dir = nil
  ---@type { dir: string, path: string }
  local repo_a = nil
  ---@type { dir: string, path: string }
  local repo_b = nil

  ---@param name string
  ---@return { dir: string, path: string }
  local function make_repo(name)
    local dir = work_dir .. "/" .. name
    vim.fn.mkdir(dir .. "/.git", "p")
    vim.cmd.cd(dir)
    return { dir = dir, path = fs.scope_path("repo") }
  end

  ---@param name string
  ---@return PeekstackSession
  local function session(name)
    return {
      items = { { uri = "file:///tmp/" .. name .. ".lua", range = {}, title = name } },
      meta = { created_at = 1, updated_at = 1 },
    }
  end

  ---@param repo { path: string }
  ---@param names string[]
  local function seed(repo, names)
    local sessions = {}
    for _, name in ipairs(names) do
      sessions[name] = session(name)
    end
    assert.is_true(store.write_sync(repo.path, { version = 2, sessions = sessions }))
  end

  ---@param repo { path: string }
  ---@return string[]
  local function session_names(repo)
    local names = vim.tbl_keys(store.read_sync(repo.path).sessions or {})
    table.sort(names)
    return names
  end

  ---@param repo { path: string }
  ---@param expected string[]
  local function wait_for_names(repo, expected)
    local ok = vim.wait(wait_timeout_ms, function()
      return vim.deep_equal(session_names(repo), expected)
    end, wait_interval_ms)
    assert.is_true(ok, "Timed out waiting for sessions: " .. table.concat(expected, ","))
  end

  before_each(function()
    config.setup({ persist = { enabled = true } })
    persist._reset_cache()
    stack._reset()
    original_cwd = vim.fn.getcwd()
    work_dir = vim.fn.tempname()
    repo_a = make_repo("a")
    repo_b = make_repo("b")
    seed(repo_a, { "a_existing" })
    seed(repo_b, { "b_existing" })
    vim.cmd.cd(repo_a.dir)
  end)

  after_each(function()
    vim.cmd.cd(original_cwd)
    pcall(vim.fn.delete, repo_a.path)
    pcall(vim.fn.delete, repo_b.path)
    pcall(vim.fn.delete, work_dir, "rf")
    persist._reset_cache()
    stack._reset()
  end)

  it("writes an async save to the repository it was requested in", function()
    local saved = nil
    persist.save_current("a_new", {
      silent = true,
      on_done = function(success)
        saved = success
      end,
    })
    vim.cmd.cd(repo_b.dir)

    local ok = vim.wait(wait_timeout_ms, function()
      return saved ~= nil
    end, wait_interval_ms)
    assert.is_true(ok, "Timed out waiting for save")
    assert.is_true(saved)
    assert.same({ "a_existing", "a_new" }, session_names(repo_a))
    assert.same({ "b_existing" }, session_names(repo_b))
  end)

  it("deletes from the repository it was requested in", function()
    seed(repo_a, { "a_existing", "a_doomed" })
    seed(repo_b, { "a_doomed", "b_existing" })

    persist.delete_session("a_doomed")
    vim.cmd.cd(repo_b.dir)

    wait_for_names(repo_a, { "a_existing" })
    assert.same({ "a_doomed", "b_existing" }, session_names(repo_b))
  end)

  it("renames in the repository it was requested in", function()
    persist.rename_session("a_existing", "a_renamed")
    vim.cmd.cd(repo_b.dir)

    wait_for_names(repo_a, { "a_renamed" })
    assert.same({ "b_existing" }, session_names(repo_b))
  end)

  it("keeps queued updates bound to their own repository", function()
    persist.save_current("a_queued", { silent = true })
    vim.cmd.cd(repo_b.dir)
    persist.save_current("b_queued", { silent = true })

    wait_for_names(repo_a, { "a_existing", "a_queued" })
    wait_for_names(repo_b, { "b_existing", "b_queued" })
  end)

  it("lists the current repository's sessions after a directory change", function()
    assert.is_not_nil(persist.list_sessions({ silent = true }).a_existing)

    vim.cmd.cd(repo_b.dir)
    local listed = persist.list_sessions({ silent = true })
    assert.is_nil(listed.a_existing)
    assert.is_not_nil(listed.b_existing)

    vim.cmd.cd(repo_a.dir)
    listed = persist.list_sessions({ silent = true })
    assert.is_not_nil(listed.a_existing)
    assert.is_nil(listed.b_existing)
  end)
end)
