describe("custom picker backend", function()
  local peekstack = require("peekstack")
  local config = require("peekstack.config")
  local registry = require("peekstack.registry")

  local original_notify
  local notifications

  before_each(function()
    original_notify = vim.notify
    notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = original_notify
    registry.register_picker("my_picker", nil)
    peekstack.setup({})
  end)

  local function has_message(pattern)
    for _, item in ipairs(notifications) do
      if tostring(item.msg):find(pattern, 1, true) then
        return true
      end
    end
    return false
  end

  it("accepts an arbitrary backend name in config", function()
    local cfg = config.setup({ picker = { backend = "my_picker" } })
    assert.equals("my_picker", cfg.picker.backend)
    assert.is_false(has_message("picker.backend"))
  end)

  it("rejects non-string backend and falls back to builtin", function()
    for _, value in ipairs({ 42, false, "" }) do
      notifications = {}
      local cfg = config.setup({ picker = { backend = value } })
      assert.equals("builtin", cfg.picker.backend)
      assert.is_true(has_message("picker.backend must be a non-empty string"))
    end
  end)

  it("keeps a picker registered before setup()", function()
    local picker = { pick = function() end }
    peekstack.register_picker("my_picker", picker)
    peekstack.setup({ picker = { backend = "my_picker" } })
    assert.equals(picker, registry.get_picker("my_picker"))
  end)

  it("keeps a picker registered after setup() across a re-run", function()
    local picker = { pick = function() end }
    peekstack.setup({})
    peekstack.register_picker("my_picker", picker)
    peekstack.setup({ picker = { backend = "my_picker" } })
    assert.equals(picker, registry.get_picker("my_picker"))
  end)

  it("dispatches multi-location results to the custom picker", function()
    local received
    peekstack.register_picker("my_picker", {
      pick = function(locations, _opts, cb)
        received = locations
        cb(nil)
      end,
    })
    peekstack.register_provider("test.custom_picker", function(_ctx, cb)
      cb({
        {
          uri = vim.uri_from_fname("/tmp/a.lua"),
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
        },
        {
          uri = vim.uri_from_fname("/tmp/b.lua"),
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
        },
      })
    end)
    peekstack.setup({ picker = { backend = "my_picker" } })

    peekstack.peek("test.custom_picker", {})

    assert.is_not_nil(received)
    assert.equals(2, #received)
  end)

  it("keeps user providers across setup() re-runs", function()
    peekstack.register_provider("test.keep", function(_ctx, cb)
      cb({})
    end)
    peekstack.setup({})
    assert.is_not_nil(registry.get_provider("test.keep"))
    assert.is_true(vim.list_contains(registry.list_providers(), "test.keep"))
  end)
end)
