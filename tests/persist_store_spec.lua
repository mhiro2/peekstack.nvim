describe("peekstack.persist.store", function()
  local store = require("peekstack.persist.store")
  local fs = require("peekstack.util.fs")

  local test_path = fs.scope_path("global")
  local wait_timeout_ms = 500
  local wait_interval_ms = 10

  ---@param path string
  ---@param data PeekstackStoreData
  local function write_and_wait(path, data)
    local done = false
    local success = false
    store.write(path, data, {
      on_done = function(ok)
        done = true
        success = ok
      end,
    })
    local ok = vim.wait(wait_timeout_ms, function()
      return done
    end, wait_interval_ms)
    assert.is_true(ok, "Timed out waiting for store write")
    assert.is_true(success, "Store write failed")
  end

  ---@param path string
  ---@return PeekstackStoreData
  local function read_and_wait(path)
    local done = false
    local result = nil
    store.read(path, {
      on_done = function(data)
        result = data
        done = true
      end,
    })
    local ok = vim.wait(wait_timeout_ms, function()
      return done
    end, wait_interval_ms)
    assert.is_true(ok, "Timed out waiting for store read")
    return result
  end

  ---@param fn fun()
  ---@return string[]
  local function capture_warnings(fn)
    local warnings = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      if level == vim.log.levels.WARN then
        table.insert(warnings, msg)
      end
    end
    local ok, err = pcall(fn)
    vim.notify = original_notify
    if not ok then
      error(err)
    end
    return warnings
  end

  ---@param path string
  ---@param content string
  local function write_raw_and_wait(path, content)
    local done = false
    vim.uv.fs_open(path, "w", 438, function(open_err, fd)
      assert.is_nil(open_err)
      assert.is_not_nil(fd)
      vim.uv.fs_write(fd, content, 0, function(write_err)
        assert.is_nil(write_err)
        vim.uv.fs_close(fd, function()
          done = true
        end)
      end)
    end)
    local ok = vim.wait(wait_timeout_ms, function()
      return done
    end, wait_interval_ms)
    assert.is_true(ok, "Timed out waiting for raw write")
  end

  ---@param path string
  local function delete_and_wait(path)
    local done = false
    vim.uv.fs_unlink(path, function()
      done = true
    end)
    local ok = vim.wait(wait_timeout_ms, function()
      return done
    end, wait_interval_ms)
    assert.is_true(ok, "Timed out waiting for file delete")
  end

  before_each(function()
    write_and_wait(test_path, { version = 2, sessions = {} })
  end)

  after_each(function()
    write_and_wait(test_path, { version = 2, sessions = {} })
  end)

  it("returns empty data when file is missing", function()
    delete_and_wait(test_path)

    local called = false
    local result = nil
    store.read(test_path, {
      on_done = function(data)
        called = true
        result = data
      end,
    })

    assert.is_false(called)

    local ok = vim.wait(wait_timeout_ms, function()
      return called
    end, wait_interval_ms)
    assert.is_true(ok, "Timed out waiting for store read callback")
    assert.same({ version = 2, sessions = {} }, result)
  end)

  it("returns data for valid store content", function()
    local data = {
      version = 2,
      sessions = {
        sample = {
          items = {},
          meta = { created_at = 1, updated_at = 2 },
        },
      },
    }
    write_and_wait(test_path, data)

    local result = read_and_wait(test_path)
    assert.same(data, result)
  end)

  it("returns nil and warns for invalid JSON", function()
    write_raw_and_wait(test_path, "{ invalid json")

    local result = "unset"
    local warnings = capture_warnings(function()
      result = read_and_wait(test_path)
    end)

    assert.is_nil(result)
    assert.is_true(#warnings > 0, "should warn about decode failure")
    assert.is_true(warnings[1]:find("Failed to decode", 1, true) ~= nil)
  end)

  it("returns nil and warns when reading fails with an I/O error", function()
    local original_fs_read = vim.uv.fs_read
    local result = "unset"
    local warnings = capture_warnings(function()
      vim.uv.fs_read = function(fd, size, offset, callback)
        if callback then
          callback("EIO: i/o error", nil)
          return
        end
        return original_fs_read(fd, size, offset)
      end
      local ok, err = pcall(function()
        result = read_and_wait(test_path)
      end)
      vim.uv.fs_read = original_fs_read
      if not ok then
        error(err)
      end
    end)

    assert.is_nil(result)
    assert.is_true(#warnings > 0 and warnings[1]:find("EIO", 1, true) ~= nil)
  end)

  it("reads the whole file when it is replaced by a larger one before opening", function()
    local original = { version = 2, sessions = {} }
    write_and_wait(test_path, original)
    local replacement = { version = 2, sessions = {} }
    for i = 1, 200 do
      replacement.sessions["session_" .. i] = { items = {}, meta = { created_at = i, updated_at = i } }
    end

    -- Swap the file in between the moment a read is requested and the open,
    -- the window where a size taken from an earlier stat would go stale.
    local original_fs_open = vim.uv.fs_open
    local result = nil
    local ok, err = pcall(function()
      vim.uv.fs_open = function(path, flags, mode, callback)
        if callback and path == test_path then
          vim.uv.fs_open = original_fs_open
          assert.is_true(store.write_sync(test_path, replacement))
        end
        return original_fs_open(path, flags, mode, callback)
      end
      result = read_and_wait(test_path)
    end)
    vim.uv.fs_open = original_fs_open
    if not ok then
      error(err)
    end

    assert.same(replacement, result)
  end)

  it("reads content larger than a single read chunk", function()
    local data = { version = 2, sessions = {} }
    for i = 1, 2000 do
      data.sessions["large_session_" .. i] = {
        items = { { uri = "file:///tmp/large_" .. i .. ".lua", title = string.rep("x", 40) } },
        meta = { created_at = i, updated_at = i },
      }
    end
    write_and_wait(test_path, data)
    assert.is_true(vim.uv.fs_stat(test_path).size > 64 * 1024)

    assert.same(data, read_and_wait(test_path))
    assert.same(data, store.read_sync(test_path))
  end)

  it("read_sync returns data for valid store content", function()
    local data = {
      version = 2,
      sessions = {
        sync_sample = {
          items = {},
          meta = { created_at = 1, updated_at = 2 },
        },
      },
    }
    write_and_wait(test_path, data)

    local result = store.read_sync(test_path)
    assert.same(data, result)
  end)

  it("read_sync returns nil and warns for invalid JSON", function()
    write_raw_and_wait(test_path, "{ invalid json")

    local result = "unset"
    local warnings = capture_warnings(function()
      result = store.read_sync(test_path)
    end)

    assert.is_nil(result)
    assert.is_true(#warnings > 0, "should warn about decode failure")
    assert.is_true(warnings[1]:find("Failed to decode", 1, true) ~= nil)
  end)

  it("read_sync returns nil when reading fails with an I/O error", function()
    local original_fs_read = vim.uv.fs_read
    local result = "unset"
    local warnings = capture_warnings(function()
      vim.uv.fs_read = function()
        return nil, "EIO: i/o error", "EIO"
      end
      local ok, err = pcall(function()
        result = store.read_sync(test_path)
      end)
      vim.uv.fs_read = original_fs_read
      if not ok then
        error(err)
      end
    end)

    assert.is_nil(result)
    assert.is_true(#warnings > 0 and warnings[1]:find("EIO", 1, true) ~= nil)
  end)

  it("read_sync returns empty data when the file is missing", function()
    delete_and_wait(test_path)
    assert.same({ version = 2, sessions = {} }, store.read_sync(test_path))
  end)

  it("write_sync stores data that can be read back", function()
    local data = {
      version = 2,
      sessions = {
        sync_write = {
          items = {},
          meta = { created_at = 10, updated_at = 20 },
        },
      },
    }

    local ok = store.write_sync(test_path, data)
    assert.is_true(ok)
    assert.same(data, store.read_sync(test_path))
  end)

  it("allows overlapping async writes to the same file", function()
    local first = {
      version = 2,
      sessions = {
        first = {
          items = {},
          meta = { created_at = 1, updated_at = 1 },
        },
      },
    }
    local second = {
      version = 2,
      sessions = {
        second = {
          items = {},
          meta = { created_at = 2, updated_at = 2 },
        },
      },
    }

    local done = 0
    local successes = {}
    store.write(test_path, first, {
      on_done = function(ok)
        done = done + 1
        successes[#successes + 1] = ok
      end,
    })
    store.write(test_path, second, {
      on_done = function(ok)
        done = done + 1
        successes[#successes + 1] = ok
      end,
    })

    local ok = vim.wait(wait_timeout_ms, function()
      return done == 2
    end, wait_interval_ms)
    assert.is_true(ok, "Timed out waiting for overlapping store writes")
    assert.is_true(successes[1])
    assert.is_true(successes[2])

    local result = read_and_wait(test_path)
    assert.equals(2, result.version)
    assert.is_true(result.sessions.first ~= nil or result.sessions.second ~= nil)
  end)

  it("write_sync returns false when payload cannot be encoded", function()
    local ok = store.write_sync(test_path, {
      version = 2,
      sessions = {},
      invalid = function() end,
    })
    assert.is_false(ok)
  end)
end)
