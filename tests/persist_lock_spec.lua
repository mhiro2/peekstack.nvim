describe("peekstack.persist.lock", function()
  local config = require("peekstack.config")
  local lock = require("peekstack.persist.lock")
  local persist = require("peekstack.persist")
  local store = require("peekstack.persist.store")

  local dir = nil
  local path = nil
  local original_notify = nil

  ---@return PeekstackSession
  local function empty_session()
    return { items = {}, meta = { created_at = 1, updated_at = 1 } }
  end

  ---@return table<string, PeekstackSession>
  local function stored_sessions()
    local data = store.read_sync(path)
    return data and data.sessions or {}
  end

  ---@return integer pid of a process that has exited
  local function exited_pid()
    local proc = vim.system({ vim.v.progpath, "--clean", "--headless", "+qa!" })
    proc:wait(5000)
    return proc.pid
  end

  ---Create the lock file as another process holding it would.
  ---@param opts? { pid?: integer|false, age_s?: integer } `pid = false` leaves the owner unknown
  local function hold_lock_elsewhere(opts)
    opts = opts or {}
    local lock_path = lock.lock_path(path)
    local pid = opts.pid
    if pid == nil then
      -- A process that keeps running for the whole test.
      pid = vim.uv.os_getppid()
    end
    vim.fn.writefile(pid and { tostring(pid) } or {}, lock_path)
    local age_s = opts.age_s
    if age_s then
      local mtime = os.time() - age_s
      assert.is_truthy(vim.uv.fs_utime(lock_path, mtime, mtime))
    end
  end

  ---@param name string
  ---@param opts? { sync?: boolean }
  ---@return fun(): boolean? result
  local function save(name, opts)
    local result = nil
    persist.save_current(name, {
      store_path = path,
      silent = true,
      sync = opts and opts.sync or false,
      on_done = function(success)
        result = success
      end,
    })
    return function()
      return result
    end
  end

  before_each(function()
    config.setup({ persist = { enabled = true } })
    persist._reset_cache()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    path = dir .. "/store.json"
    original_notify = vim.notify
  end)

  after_each(function()
    vim.notify = original_notify
    persist._reset_cache()
    vim.fn.delete(dir, "rf")
  end)

  it("waits for another process to release the lock before reading the store", function()
    hold_lock_elsewhere()
    local result = save("mine")

    vim.wait(60, function()
      return false
    end, 10)
    assert.is_nil(result())

    -- The other process writes its session, then releases the lock.
    assert.is_true(store.write_sync(path, { version = 2, sessions = { theirs = empty_session() } }))
    vim.fn.delete(lock.lock_path(path))

    assert.is_true(vim.wait(3000, function()
      return result() ~= nil
    end, 10))
    assert.is_true(result())
    local sessions = stored_sessions()
    assert.is_not_nil(sessions.mine)
    assert.is_not_nil(sessions.theirs)
    assert.equals(0, vim.fn.filereadable(lock.lock_path(path)))
  end)

  it("takes over a lock left behind by a process that exited", function()
    hold_lock_elsewhere({ pid = exited_pid() })
    local result = save("after_exit", { sync = true })

    assert.is_true(result())
    assert.is_not_nil(stored_sessions().after_exit)
    assert.equals(0, vim.fn.filereadable(lock.lock_path(path)))
  end)

  it("takes over an old lock whose owner is unknown", function()
    hold_lock_elsewhere({ pid = false, age_s = 60 })
    local result = save("after_unknown", { sync = true })

    assert.is_true(result())
    assert.is_not_nil(stored_sessions().after_unknown)
  end)

  it("fails without writing while a running process keeps the lock, however old", function()
    local warnings = {}
    vim.notify = function(msg)
      warnings[#warnings + 1] = msg
    end
    hold_lock_elsewhere({ age_s = 60 })
    local result = save("blocked", { sync = true })

    assert.is_false(result())
    assert.equals(0, vim.fn.filereadable(path))
    assert.equals(1, vim.fn.filereadable(lock.lock_path(path)))
    assert.is_truthy(warnings[1] and warnings[1]:find("Timed out waiting for another Neovim", 1, true))
  end)

  it("leaves a lock alone that replaced the abandoned one it found", function()
    hold_lock_elsewhere({ pid = exited_pid() })
    local lock_path = lock.lock_path(path)
    local guard_path = lock_path .. ".takeover"
    local original_open = vim.uv.fs_open
    local replaced = false
    -- Another instance takes the abandoned lock over and acquires a new one
    -- between this instance's check and its own takeover.
    vim.uv.fs_open = function(file, ...)
      if file == guard_path and not replaced then
        replaced = true
        vim.fn.delete(lock_path)
        vim.fn.writefile({ tostring(vim.uv.os_getppid()) }, lock_path)
        local future = os.time() + 5
        vim.uv.fs_utime(lock_path, future, future)
      end
      return original_open(file, ...)
    end
    vim.notify = function() end
    local ok, err = pcall(function()
      local result = save("raced", { sync = true })
      assert.is_false(result())
    end)
    vim.uv.fs_open = original_open
    if not ok then
      error(err)
    end

    assert.is_true(replaced)
    assert.equals(tostring(vim.uv.os_getppid()), vim.fn.readfile(lock_path)[1])
    assert.equals(0, vim.fn.filereadable(guard_path))
    assert.is_nil(stored_sessions().raced)
  end)

  it("removes a takeover guard left behind by a process that exited", function()
    hold_lock_elsewhere({ pid = exited_pid() })
    local guard_path = lock.lock_path(path) .. ".takeover"
    vim.fn.writefile({}, guard_path)
    local old = os.time() - 60
    assert.is_truthy(vim.uv.fs_utime(guard_path, old, old))

    local result = save("after_guard", { sync = true })
    assert.is_true(result())
    assert.is_not_nil(stored_sessions().after_guard)
    assert.equals(0, vim.fn.filereadable(guard_path))
  end)

  it("keeps every session saved concurrently by separate Neovim processes", function()
    local count = 30
    local start_file = dir .. "/start"
    local script = dir .. "/save_sessions.lua"
    vim.fn.writefile({
      "local root, store_path, prefix, count, start_file = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]",
      "vim.opt.runtimepath:append(root)",
      "require('peekstack.config').setup({ persist = { enabled = true } })",
      "local orchestrator = require('peekstack.persist.orchestrator')",
      "local sessions = require('peekstack.persist.sessions')",
      "while not vim.uv.fs_stat(start_file) do vim.uv.sleep(5) end",
      "for i = 1, count do",
      "  local ok = orchestrator.update_sync(store_path, function(data)",
      "    sessions.upsert(data, prefix .. i, {})",
      "    return true",
      "  end)",
      "  if not ok then os.exit(1) end",
      "  vim.uv.sleep(2)",
      "end",
    }, script)

    local root = vim.fn.getcwd()
    local procs = {}
    for _, prefix in ipairs({ "first_", "second_" }) do
      procs[#procs + 1] = vim.system({
        vim.v.progpath,
        "--headless",
        "--clean",
        "-l",
        script,
        root,
        path,
        prefix,
        tostring(count),
        start_file,
      }, { text = true })
    end
    vim.fn.writefile({}, start_file)

    for _, proc in ipairs(procs) do
      local done = proc:wait(10000)
      assert.equals(0, done.code, done.stderr)
    end

    local sessions = stored_sessions()
    for _, prefix in ipairs({ "first_", "second_" }) do
      for i = 1, count do
        assert.is_not_nil(sessions[prefix .. i], "missing session " .. prefix .. i)
      end
    end
  end)
end)
