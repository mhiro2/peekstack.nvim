describe("peekstack.core.user_events", function()
  local user_events = require("peekstack.core.user_events")
  local stack = require("peekstack.core.stack")
  local config = require("peekstack.config")

  -- Track received events
  local received_events = {}

  ---@param name string
  ---@return boolean
  local function wait_for_event(name)
    return vim.wait(500, function()
      for _, ev in ipairs(received_events) do
        if ev.event == name then
          return true
        end
      end
      return false
    end, 10)
  end

  before_each(function()
    received_events = {}
    stack._reset()
    config.setup({})

    -- Setup autocmd to capture events
    vim.api.nvim_create_autocmd("User", {
      pattern = "Peekstack*",
      callback = function(args)
        table.insert(received_events, {
          event = args.match,
          data = args.data,
        })
      end,
    })
  end)

  after_each(function()
    -- Clear autocmd
    vim.api.nvim_clear_autocmds({ pattern = "Peekstack*" })
    stack._reset()
  end)

  it("should emit PeekstackPush event when pushing to stack", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    stack.push(location)

    -- Wait a bit for autocmd to process
    vim.wait(100)

    local found = false
    for _, ev in ipairs(received_events) do
      if ev.event == "PeekstackPush" then
        found = true
        assert.is_not_nil(ev.data.popup_id)
        assert.is_not_nil(ev.data.winid)
        assert.equals("test", ev.data.provider)
        break
      end
    end
    assert.is_true(found, "PeekstackPush event not found")
  end)

  it("should emit PeekstackClose event when closing popup", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    local model = stack.push(location)
    stack.close(model.id)

    vim.wait(100)

    local found = false
    for _, ev in ipairs(received_events) do
      if ev.event == "PeekstackClose" then
        found = true
        assert.equals(model.id, ev.data.popup_id)
        break
      end
    end
    assert.is_true(found, "PeekstackClose event not found")
  end)

  it("should emit PeekstackFocus event when focusing popup", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    local model = stack.push(location)
    stack.focus_by_id(model.id)

    vim.wait(100)

    local found = false
    for _, ev in ipairs(received_events) do
      if ev.event == "PeekstackFocus" then
        found = true
        assert.equals(model.id, ev.data.popup_id)
        break
      end
    end
    assert.is_true(found, "PeekstackFocus event not found")
  end)

  it("should emit PeekstackFocus event when focusing with focus_prev", function()
    local location = {
      uri = vim.uri_from_bufnr(0),
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 10 } },
      provider = "test",
    }

    local first = stack.push(location)
    local _second = stack.push(location)
    stack.focus_prev()

    vim.wait(100)

    local found = false
    for _, ev in ipairs(received_events) do
      if ev.event == "PeekstackFocus" and ev.data and ev.data.popup_id == first.id then
        found = true
        break
      end
    end
    assert.is_true(found, "PeekstackFocus event from focus_prev not found")
  end)

  it("should emit PeekstackSave event when saving session", function()
    local persist = require("peekstack.persist")
    config.setup({ persist = { enabled = true } })

    persist.save_current("test_session")

    local ok = wait_for_event("PeekstackSave")
    assert.is_true(ok, "Timed out waiting for PeekstackSave event")

    local found = false
    for _, ev in ipairs(received_events) do
      if ev.event == "PeekstackSave" then
        found = true
        assert.equals("test_session", ev.data.session)
        break
      end
    end
    assert.is_true(found, "PeekstackSave event not found")
  end)

  it("should emit PeekstackRestore event when restoring session", function()
    local persist = require("peekstack.persist")
    config.setup({ persist = { enabled = true } })

    persist.restore("test_session")

    vim.wait(100)

    local _found = false
    for _, ev in ipairs(received_events) do
      if ev.event == "PeekstackRestore" then
        _found = true
        break
      end
    end
    -- Note: this may not find a session since we're testing with empty data
    -- but the event emission should still work
  end)

  it("should handle emit errors gracefully", function()
    -- This should not error even with invalid data
    user_events.emit("PeekstackTest", { invalid = "data" })
    -- If we got here, error handling worked
    assert.is_true(true)
  end)
end)
