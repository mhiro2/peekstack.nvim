describe("peekstack.persist.store", function()
  local store = require("peekstack.persist.store")
  local fs = require("peekstack.util.fs")

  local test_scope = "global"
  local wait_timeout_ms = 500
  local wait_interval_ms = 10

  ---@param scope string
  ---@param data PeekstackStoreData
  local function write_and_wait(scope, data)
    local done = false
    local success = false
    store.write(scope, data, {
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

  ---@param scope string
  ---@return PeekstackStoreData
  local function read_and_wait(scope)
    local done = false
    local result = nil
    store.read(scope, {
      on_done = function(data)
        result = data
        done = true
      end,
    })
    local ok = vim.wait(wait_timeout_ms, function()
      return done
    end, wait_interval_ms)
    assert.is_true(ok, "Timed out waiting for store read")
    return result or { version = 2, sessions = {} }
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
    write_and_wait(test_scope, { version = 2, sessions = {} })
  end)

  after_each(function()
    write_and_wait(test_scope, { version = 2, sessions = {} })
  end)

  it("returns empty data when file is missing", function()
    local path = fs.scope_path(test_scope)
    delete_and_wait(path)

    local called = false
    local result = nil
    store.read(test_scope, {
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
    write_and_wait(test_scope, data)

    local result = read_and_wait(test_scope)
    assert.same(data, result)
  end)

  it("returns empty data for invalid JSON", function()
    local path = fs.scope_path(test_scope)
    write_raw_and_wait(path, "{ invalid json")

    local result = read_and_wait(test_scope)
    assert.same({ version = 2, sessions = {} }, result)
  end)
end)
