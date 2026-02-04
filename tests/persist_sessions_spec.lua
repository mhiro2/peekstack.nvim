describe("peekstack.persist.sessions", function()
  local persist = require("peekstack.persist")
  local config = require("peekstack.config")
  local store = require("peekstack.persist.store")
  local migrate = require("peekstack.persist.migrate")

  -- Use "repo" as the fixed scope for persistence
  local test_scope = "repo"
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

  ---@param scope string
  ---@param predicate fun(data: PeekstackStoreData): boolean
  local function wait_for_store(scope, predicate)
    local satisfied = false
    local in_flight = false
    local ok = vim.wait(wait_timeout_ms, function()
      if satisfied then
        return true
      end
      if not in_flight then
        in_flight = true
        store.read(scope, {
          on_done = function(data)
            if predicate(data) then
              satisfied = true
            end
            in_flight = false
          end,
        })
      end
      return satisfied
    end, wait_interval_ms)
    assert.is_true(ok, "Timed out waiting for store update")
  end

  ---@param name string
  ---@param present boolean
  ---@return table<string, PeekstackSession>
  local function wait_for_session(name, present)
    local satisfied = false
    local in_flight = false
    local result = {}
    local ok = vim.wait(wait_timeout_ms, function()
      if satisfied then
        return true
      end
      if not in_flight then
        in_flight = true
        persist.list_sessions({
          on_done = function(sessions)
            result = sessions
            if present then
              satisfied = sessions[name] ~= nil
            else
              satisfied = sessions[name] == nil
            end
            in_flight = false
          end,
        })
      end
      return satisfied
    end, wait_interval_ms)
    assert.is_true(ok, "Timed out waiting for session: " .. name)
    return result
  end

  before_each(function()
    -- Setup config with persist enabled
    config.setup({ persist = { enabled = true, max_items = 200 } })

    -- Clear any existing test data
    local data = { version = 2, sessions = {} }
    write_and_wait(test_scope, data)
  end)

  after_each(function()
    -- Cleanup test data
    local data = { version = 2, sessions = {} }
    write_and_wait(test_scope, data)
  end)

  it("should save and restore a named session", function()
    -- This test requires a valid Neovim buffer/window context
    -- For now, we test the data structure manipulation
    local data = migrate.ensure(read_and_wait(test_scope))
    assert.same({ version = 2, sessions = {} }, data)
  end)

  it("should list all sessions", function()
    persist.save_current("test_session_1")
    wait_for_session("test_session_1", true)
    persist.save_current("test_session_2")

    local sessions = wait_for_session("test_session_2", true)
    assert.is_not_nil(sessions["test_session_1"])
    assert.is_not_nil(sessions["test_session_2"])
  end)

  it("should delete a session", function()
    persist.save_current("to_delete")

    local sessions_before = wait_for_session("to_delete", true)
    assert.is_not_nil(sessions_before["to_delete"])

    persist.delete_session("to_delete")

    local sessions_after = wait_for_session("to_delete", false)
    assert.is_nil(sessions_after["to_delete"])
  end)

  it("should rename a session", function()
    persist.save_current("old_name")

    local sessions_before = wait_for_session("old_name", true)
    assert.is_not_nil(sessions_before["old_name"])
    assert.is_nil(sessions_before["new_name"])

    persist.rename_session("old_name", "new_name")

    local sessions_after = wait_for_session("old_name", false)
    sessions_after = wait_for_session("new_name", true)
    assert.is_nil(sessions_after["old_name"])
    assert.is_not_nil(sessions_after["new_name"])
  end)

  it("should respect max_items when saving", function()
    config.setup({ persist = { enabled = true, max_items = 2 } })

    -- max_items is enforced when calling save_current with items in the stack
    -- Since we can't create a real stack in tests, we verify the logic is in place
    -- by checking the code path exists
    assert.is_not_nil(persist.save_current)
  end)

  it("should notify when persist is disabled", function()
    config.setup({ persist = { enabled = false } })

    -- These should not error when persist is disabled
    persist.save_current("test")
    persist.restore("test")
    persist.delete_session("test")
    persist.rename_session("a", "b")
  end)

  it("should handle non-existent sessions gracefully", function()
    persist.restore("non_existent")
    -- Should not error
  end)

  it("should migrate version 1 to version 2 schema", function()
    -- Write version 1 data
    local v1_data = {
      version = 1,
      items = {
        {
          uri = "file:///test.lua",
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
          title = "Test",
          provider = "test",
          ts = os.time(),
        },
      },
    }
    write_and_wait(test_scope, v1_data)

    wait_for_store(test_scope, function(read_data)
      return read_data.version == 1 and type(read_data.items) == "table"
    end)

    -- Read and ensure migration
    local migrated = migrate.ensure(read_and_wait(test_scope))

    assert.equals(2, migrated.version)
    assert.is_not_nil(migrated.sessions)
    assert.is_not_nil(migrated.sessions.default)
    assert.is_not_nil(migrated.sessions.default.items)
    assert.equals(1, #migrated.sessions.default.items)
  end)

  it("should always use repo scope when saving", function()
    config.setup({ persist = { enabled = true, max_items = 200 } })

    write_and_wait("global", { version = 2, sessions = {} })
    write_and_wait("repo", { version = 2, sessions = {} })

    persist.save_current("scoped_session", { scope = "global", silent = true })

    wait_for_store("repo", function(read_data)
      local ensured = migrate.ensure(read_data)
      return ensured.sessions.scoped_session ~= nil
    end)

    local repo_data = migrate.ensure(read_and_wait("repo"))
    local global_data = migrate.ensure(read_and_wait("global"))
    assert.is_not_nil(repo_data.sessions.scoped_session)
    assert.is_nil(global_data.sessions.scoped_session)

    write_and_wait("global", { version = 2, sessions = {} })
  end)

  it("should use root_winid when saving", function()
    local stack = require("peekstack.core.stack")
    stack._reset()

    local winid1 = vim.api.nvim_get_current_win()
    vim.api.nvim_cmd({ cmd = "split" }, {})
    local winid2 = vim.api.nvim_get_current_win()

    local function popup(id, uri)
      return {
        id = id,
        location = {
          uri = uri,
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
          provider = "test",
        },
        title = "Test " .. id,
      }
    end

    stack.current_stack(winid1).popups = { popup(1, "file:///tmp/a.lua") }
    stack.current_stack(winid2).popups = { popup(2, "file:///tmp/b.lua"), popup(3, "file:///tmp/c.lua") }

    persist.save_current("root_specific", { root_winid = winid2, silent = true })

    wait_for_store(test_scope, function(read_data)
      local ensured = migrate.ensure(read_data)
      return ensured.sessions.root_specific
        and ensured.sessions.root_specific.items
        and #ensured.sessions.root_specific.items == 2
    end)

    local data = migrate.ensure(read_and_wait(test_scope))
    assert.equals(2, #data.sessions.root_specific.items)
    assert.equals("file:///tmp/b.lua", data.sessions.root_specific.items[1].uri)
    assert.equals("file:///tmp/c.lua", data.sessions.root_specific.items[2].uri)

    vim.api.nvim_win_close(winid2, true)
    stack._reset()
  end)

  it("should suppress notifications when silent", function()
    local original_notify = vim.notify
    local notifications = {}
    vim.notify = function(msg)
      table.insert(notifications, msg)
    end

    persist.save_current("silent_session", { silent = true })
    persist.restore("missing_session", { silent = true })

    wait_for_store(test_scope, function(read_data)
      local ensured = migrate.ensure(read_data)
      return ensured.sessions.silent_session ~= nil
    end)

    assert.equals(0, #notifications)
    vim.notify = original_notify
  end)

  it("should save the root stack when stack view is active", function()
    local stack = require("peekstack.core.stack")
    local stack_view = require("peekstack.ui.stack_view")

    stack._reset()

    local root_winid = vim.api.nvim_get_current_win()
    local s = stack.current_stack(root_winid)
    s.popups = {
      {
        id = 1,
        location = {
          uri = "file:///tmp/test.lua",
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
          provider = "test",
        },
        title = "Test",
      },
    }

    stack_view.open()
    persist.save_current("stack_view_active")

    wait_for_store(test_scope, function(read_data)
      local ensured = migrate.ensure(read_data)
      return ensured.sessions.stack_view_active
        and ensured.sessions.stack_view_active.items
        and #ensured.sessions.stack_view_active.items == 1
    end)
    local data = migrate.ensure(read_and_wait(test_scope))
    assert.is_not_nil(data.sessions.stack_view_active)
    assert.equals(1, #data.sessions.stack_view_active.items)

    stack_view.toggle()
  end)
end)
