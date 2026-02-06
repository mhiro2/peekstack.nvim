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
          scope = "buffer",
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

  it("clears persist auto timer on repeated setup", function()
    peekstack.setup({
      persist = {
        enabled = true,
        auto = {
          enabled = true,
          restore = false,
          save = true,
          save_on_leave = false,
          debounce_ms = 200,
        },
      },
    })

    assert.is_true(auto.schedule_save({ root_winid = vim.api.nvim_get_current_win() }))
    assert.is_not_nil(timer_store.persist_auto)

    peekstack.setup({
      persist = {
        enabled = false,
        auto = {
          enabled = false,
        },
      },
    })

    assert.is_nil(timer_store.persist_auto)
  end)
end)
