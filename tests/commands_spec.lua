describe("peekstack.commands", function()
  local commands = require("peekstack.commands")
  local persist = require("peekstack.persist")
  local original_list_sessions = nil

  before_each(function()
    commands._reset()
    original_list_sessions = persist.list_sessions
  end)

  after_each(function()
    if original_list_sessions then
      persist.list_sessions = original_list_sessions
    end
    commands._reset()
  end)

  it("returns session names without async list dependency", function()
    local called_with_opts = false
    persist.list_sessions = function(opts)
      if opts ~= nil then
        called_with_opts = true
      end
      return {
        alpha = { items = {}, meta = { created_at = 1, updated_at = 1 } },
        beta = { items = {}, meta = { created_at = 1, updated_at = 1 } },
      }
    end

    commands.setup()
    local names = vim.fn.getcompletion("PeekstackRestoreSession ", "cmdline")
    table.sort(names)

    assert.same({ "alpha", "beta" }, names)
    assert.is_false(called_with_opts)
  end)
end)
