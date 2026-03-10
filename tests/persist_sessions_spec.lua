describe("peekstack.persist.sessions", function()
  local persist = require("peekstack.persist")
  local config = require("peekstack.config")
  local stack = require("peekstack.core.stack")
  local store = require("peekstack.persist.store")
  local migrate = require("peekstack.persist.migrate")

  -- Use "repo" as the fixed scope for persistence
  local test_scope = "repo"
  local wait_timeout_ms = 500
  local wait_interval_ms = 10
  local temp_paths = {}

  local function cleanup_stack()
    for root_winid, model in pairs(stack._all_stacks()) do
      if model and model.popups and #model.popups > 0 then
        pcall(stack.close_all, root_winid)
      end
    end
    stack._reset()
  end

  local function cleanup_temp_files()
    for _, path in ipairs(temp_paths) do
      pcall(vim.fn.delete, path)
    end
    temp_paths = {}
  end

  ---@param name string
  ---@param lines? string[]
  ---@return string
  local function make_file(name, lines)
    local path = vim.fn.tempname() .. "_" .. name .. ".lua"
    vim.fn.writefile(lines or { "line1", "line2", "line3", "line4" }, path)
    temp_paths[#temp_paths + 1] = path
    return path
  end

  ---@param path string
  ---@param line? integer
  ---@return PeekstackLocation
  local function make_location(path, line)
    local target_line = line or 0
    return {
      uri = vim.uri_from_fname(path),
      range = {
        start = { line = target_line, character = 0 },
        ["end"] = { line = target_line, character = 1 },
      },
      provider = "test",
    }
  end

  ---@param name string
  ---@param opts? { title?: string, line?: integer, lines?: string[] }
  ---@return { path: string, model: PeekstackPopupModel }
  local function push_popup(name, opts)
    local path = make_file(name, opts and opts.lines or nil)
    local model = stack.push(make_location(path, opts and opts.line or 0), {
      title = opts and opts.title or name,
    })
    assert.is_not_nil(model)
    return { path = path, model = model }
  end

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
    persist._reset_cache()
    cleanup_stack()

    -- Clear any existing test data
    local data = { version = 2, sessions = {} }
    write_and_wait(test_scope, data)
  end)

  after_each(function()
    cleanup_stack()
    cleanup_temp_files()
    persist._reset_cache()

    -- Cleanup test data
    local data = { version = 2, sessions = {} }
    write_and_wait(test_scope, data)
  end)

  it("should save and restore a named session", function()
    local first = push_popup("save_restore_a", { title = "Alpha", line = 0 })
    local second = push_popup("save_restore_b", { title = "Beta", line = 1 })

    local saved = nil
    persist.save_current("named_session", {
      silent = true,
      sync = true,
      on_done = function(success)
        saved = success
      end,
    })

    assert.is_true(saved)

    local persisted = migrate.ensure(read_and_wait(test_scope))
    local session = persisted.sessions.named_session
    assert.is_not_nil(session)
    assert.equals(2, #session.items)
    assert.equals(first.model.location.uri, session.items[1].uri)
    assert.equals(second.model.location.uri, session.items[2].uri)
    assert.equals("Alpha", session.items[1].title)
    assert.equals("Beta", session.items[2].title)

    cleanup_stack()

    local restored = nil
    persist.restore("named_session", {
      silent = true,
      on_done = function(result)
        restored = result
      end,
    })

    local waited = vim.wait(wait_timeout_ms, function()
      return restored ~= nil
    end, wait_interval_ms)
    assert.is_true(waited, "Timed out waiting for restore callback")
    assert.is_true(restored)

    local restored_popups = stack.list()
    assert.equals(2, #restored_popups)
    assert.equals(first.model.location.uri, restored_popups[1].location.uri)
    assert.equals(second.model.location.uri, restored_popups[2].location.uri)
    assert.equals("Alpha", restored_popups[1].title)
    assert.equals("Beta", restored_popups[2].title)
  end)

  it("should list all sessions", function()
    push_popup("list_session_a", { title = "List A" })
    persist.save_current("test_session_1", { silent = true, sync = true })
    cleanup_stack()

    push_popup("list_session_b", { title = "List B" })
    persist.save_current("test_session_2", { silent = true, sync = true })
    persist._reset_cache()

    local sessions = persist.list_sessions()
    assert.is_not_nil(sessions["test_session_1"])
    assert.is_not_nil(sessions["test_session_2"])
    assert.equals(1, #sessions["test_session_1"].items)
    assert.equals("List A", sessions["test_session_1"].items[1].title)
    assert.equals(1, #sessions["test_session_2"].items)
    assert.equals("List B", sessions["test_session_2"].items[1].title)
  end)

  it("should save synchronously when sync is enabled", function()
    local done = nil
    persist.save_current("sync_session", {
      silent = true,
      sync = true,
      on_done = function(success)
        done = success
      end,
    })

    assert.is_true(done)

    local data = migrate.ensure(read_and_wait(test_scope))
    assert.is_not_nil(data.sessions.sync_session)
  end)

  it("should load sessions synchronously on first list_sessions call", function()
    write_and_wait(test_scope, {
      version = 2,
      sessions = {
        sync_loaded = {
          items = {},
          meta = { created_at = 1, updated_at = 1 },
        },
      },
    })
    persist._reset_cache()

    local sessions = persist.list_sessions()
    assert.is_not_nil(sessions.sync_loaded)
  end)

  it("should delete a session", function()
    push_popup("delete_session", { title = "Delete me" })
    persist.save_current("to_delete", { silent = true, sync = true })

    local sessions_before = wait_for_session("to_delete", true)
    assert.is_not_nil(sessions_before["to_delete"])

    persist.delete_session("to_delete")

    local sessions_after = wait_for_session("to_delete", false)
    assert.is_nil(sessions_after["to_delete"])

    local data = migrate.ensure(read_and_wait(test_scope))
    assert.is_nil(data.sessions.to_delete)
  end)

  it("should rename a session", function()
    push_popup("rename_session", { title = "Rename me" })
    persist.save_current("old_name", { silent = true, sync = true })

    local sessions_before = wait_for_session("old_name", true)
    assert.is_not_nil(sessions_before["old_name"])
    assert.is_nil(sessions_before["new_name"])

    persist.rename_session("old_name", "new_name")

    local sessions_after = wait_for_session("old_name", false)
    sessions_after = wait_for_session("new_name", true)
    assert.is_nil(sessions_after["old_name"])
    assert.is_not_nil(sessions_after["new_name"])
    assert.equals("Rename me", sessions_after["new_name"].items[1].title)
  end)

  it("should respect max_items when saving", function()
    config.setup({ persist = { enabled = true, max_items = 2 } })
    local first = push_popup("max_items_a", { title = "First" })
    local second = push_popup("max_items_b", { title = "Second" })
    local third = push_popup("max_items_c", { title = "Third" })

    persist.save_current("trimmed", { silent = true, sync = true })

    local data = migrate.ensure(read_and_wait(test_scope))
    local items = data.sessions.trimmed.items
    assert.equals(2, #items)
    assert.equals(second.model.location.uri, items[1].uri)
    assert.equals(third.model.location.uri, items[2].uri)
    assert.is_not.equals(first.model.location.uri, items[1].uri)
  end)

  it("should notify when persist is disabled", function()
    config.setup({ persist = { enabled = false } })
    local original_notify = vim.notify
    local messages = {}
    vim.notify = function(msg)
      table.insert(messages, msg)
    end

    -- These should not error when persist is disabled
    persist.save_current("test")
    persist.restore("test")
    local sessions = persist.list_sessions()
    assert.same({}, sessions)
    local callback_called = false
    persist.list_sessions({
      on_done = function()
        callback_called = true
      end,
    })
    assert.is_false(callback_called)
    persist.delete_session("test")
    persist.rename_session("a", "b")
    assert.is_true(vim.list_contains(messages, "[peekstack] peekstack.persist is disabled"))
    vim.notify = original_notify
  end)

  it("should handle non-existent sessions gracefully", function()
    persist.restore("non_existent")
    -- Should not error
  end)

  it("should batch reflow when restoring a session", function()
    local original_push = stack.push
    local original_reflow = stack.reflow

    local test_data = {
      version = 2,
      sessions = {
        batched = {
          items = {
            {
              uri = "file:///tmp/a.lua",
              range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
              provider = "test",
              ts = os.time(),
            },
            {
              uri = "file:///tmp/b.lua",
              range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 1 } },
              provider = "test",
              ts = os.time(),
            },
          },
          meta = { created_at = os.time(), updated_at = os.time() },
        },
      },
    }
    write_and_wait(test_scope, test_data)

    local pushed_opts = {}
    local reflow_calls = 0

    local ok, err = pcall(function()
      stack.push = function(_loc, opts)
        table.insert(pushed_opts, opts or {})
        return { id = #pushed_opts }
      end
      stack.reflow = function(_winid)
        reflow_calls = reflow_calls + 1
      end

      local restored = nil
      persist.restore("batched", {
        silent = true,
        on_done = function(result)
          restored = result
        end,
      })

      local waited = vim.wait(wait_timeout_ms, function()
        return restored ~= nil
      end, wait_interval_ms)
      assert.is_true(waited, "Timed out waiting for restore callback")

      assert.is_true(restored)
      assert.equals(2, #pushed_opts)
      assert.is_true(pushed_opts[1].defer_reflow)
      assert.is_true(pushed_opts[2].defer_reflow)
      assert.equals(1, reflow_calls)
    end)

    stack.push = original_push
    stack.reflow = original_reflow

    if not ok then
      error(err)
    end
  end)

  it("should restore session items even when title and provider are missing", function()
    local original_push = stack.push
    local original_reflow = stack.reflow

    write_and_wait(test_scope, {
      version = 2,
      sessions = {
        optional_fields = {
          items = {
            {
              uri = "file:///tmp/optional.lua",
              range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
              ts = os.time(),
            },
          },
          meta = { created_at = os.time(), updated_at = os.time() },
        },
      },
    })

    local pushed_loc = nil
    local pushed_opts = nil
    local reflow_calls = 0

    local ok, err = pcall(function()
      stack.push = function(loc, opts)
        pushed_loc = vim.deepcopy(loc)
        pushed_opts = vim.deepcopy(opts or {})
        return { id = 1 }
      end
      stack.reflow = function(_winid)
        reflow_calls = reflow_calls + 1
      end

      local restored = nil
      persist.restore("optional_fields", {
        silent = true,
        on_done = function(result)
          restored = result
        end,
      })

      local waited = vim.wait(wait_timeout_ms, function()
        return restored ~= nil
      end, wait_interval_ms)
      assert.is_true(waited, "Timed out waiting for restore callback")

      assert.is_true(restored)
      assert.equals("persist", pushed_loc.provider)
      assert.is_nil(pushed_opts.title)
      assert.is_true(pushed_opts.defer_reflow)
      assert.equals(1, reflow_calls)
    end)

    stack.push = original_push
    stack.reflow = original_reflow

    if not ok then
      error(err)
    end
  end)

  it("should invoke on_done with false when persist is disabled", function()
    config.setup({ persist = { enabled = false } })

    local save_done = nil
    local restore_done = nil

    persist.save_current("disabled_save", {
      silent = true,
      on_done = function(success)
        save_done = success
      end,
    })
    persist.restore("disabled_restore", {
      silent = true,
      on_done = function(restored)
        restore_done = restored
      end,
    })

    assert.is_false(save_done)
    assert.is_false(restore_done)
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

  it("should always use repo storage when saving", function()
    config.setup({ persist = { enabled = true, max_items = 200 } })

    write_and_wait("global", { version = 2, sessions = {} })
    write_and_wait("repo", { version = 2, sessions = {} })

    persist.save_current("scoped_session", { silent = true })

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

    local save_done = nil
    local restore_done = nil

    persist.save_current("silent_session", {
      silent = true,
      on_done = function(success)
        save_done = success
      end,
    })
    persist.restore("missing_session", {
      silent = true,
      on_done = function(restored)
        restore_done = restored
      end,
    })

    local waited = vim.wait(wait_timeout_ms, function()
      return save_done ~= nil and restore_done ~= nil
    end, wait_interval_ms)
    assert.is_true(waited, "Timed out waiting for silent persist callbacks")
    assert.is_true(save_done)
    assert.is_false(restore_done)
    assert.is_false(vim.list_contains(notifications, "[peekstack] Session saved: silent_session"))
    assert.is_false(vim.list_contains(notifications, "[peekstack] No saved session: missing_session"))
    vim.notify = original_notify
  end)

  it("should save the root stack when stack view is active", function()
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
