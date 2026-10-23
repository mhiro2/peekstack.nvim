describe("peekstack.setup idempotent", function()
  local peekstack = require("peekstack")
  local auto = require("peekstack.persist.auto")
  local commands = require("peekstack.commands")
  local persist = require("peekstack.persist")
  local timer_store = require("peekstack.util.timer").get_store()
  local stack = require("peekstack.core.stack")

  local original_notify = nil
  local notifications = {}

  before_each(function()
    original_notify = vim.notify
    notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    stack._reset()
    auto._reset()
    persist._reset_cache()
    commands._reset()
  end)

  after_each(function()
    vim.notify = original_notify
    commands._reset()
    persist._reset_cache()
    auto._reset()
    stack._reset()
  end)

  it("drops disabled providers on repeated setup", function()
    peekstack.setup({
      providers = {
        marks = {
          enable = true,
        },
      },
    })

    peekstack.setup({
      providers = {
        marks = {
          enable = false,
        },
      },
    })

    peekstack.peek("marks.buffer", {})

    local found = false
    for _, item in ipairs(notifications) do
      if item.msg:find("Unknown provider: marks.buffer", 1, true) then
        found = true
        break
      end
    end
    assert.is_true(found, "marks provider should not remain registered after re-setup")
  end)

  it("closes the pending persist auto timer on repeated setup", function()
    local auto_opts = {
      persist = {
        enabled = true,
        auto = {
          enabled = true,
          restore = false,
          save = true,
          save_on_leave = false,
          debounce_ms = 50,
        },
      },
    }
    peekstack.setup(auto_opts)

    local saves = 0
    local original_save_current = persist.save_current
    persist.save_current = function()
      saves = saves + 1
    end

    local ok, err = pcall(function()
      assert.is_true(auto.schedule_save({ root_winid = vim.api.nvim_get_current_win() }))
      local handle = timer_store.persist_auto
      assert.is_not_nil(handle)
      assert.is_true(handle:is_active())

      -- Auto save stays enabled, so only setup discarding the pending save
      -- keeps it from being written once the debounce elapses.
      peekstack.setup(auto_opts)

      assert.is_nil(timer_store.persist_auto)
      assert.is_true(handle:is_closing())

      vim.wait(200, function()
        return saves > 0
      end, 10)
      assert.equals(0, saves)
    end)
    persist.save_current = original_save_current
    if not ok then
      error(err)
    end
  end)
end)
