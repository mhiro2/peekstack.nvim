describe("peekstack.commands", function()
  local commands = require("peekstack.commands")
  local persist = require("peekstack.persist")
  local original_list_sessions = nil
  local original_select = nil

  before_each(function()
    commands._reset()
    original_list_sessions = persist.list_sessions
    original_select = vim.ui.select
  end)

  after_each(function()
    if original_list_sessions then
      persist.list_sessions = original_list_sessions
    end
    if original_select then
      vim.ui.select = original_select
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

  it("handles missing session meta in list command", function()
    local prompts = {}
    persist.list_sessions = function(opts)
      assert.is_truthy(opts)
      assert.is_truthy(opts.on_done)
      opts.on_done({
        broken = {
          items = { { uri = "file:///tmp/a.lua" } },
        },
      })
      return {}
    end

    vim.ui.select = function(_items, opts, on_choice)
      table.insert(prompts, opts.prompt)
      if opts.prompt == "Select a session" then
        on_choice("broken")
        return
      end
      on_choice("Info only")
    end

    commands.setup()
    vim.api.nvim_cmd({ cmd = "PeekstackListSessions" }, {})

    assert.equals("Select a session", prompts[1])
    assert.equals("broken: 1 items (updated: unknown)", prompts[2])
  end)

  it("includes extended providers in quick peek completion", function()
    commands.setup()
    local names = vim.fn.getcompletion("PeekstackQuickPeek ", "cmdline")

    assert.is_true(vim.list_contains(names, "lsp.declaration"))
    assert.is_true(vim.list_contains(names, "diagnostics.in_buffer"))
    assert.is_true(vim.list_contains(names, "marks.buffer"))
    assert.is_true(vim.list_contains(names, "marks.global"))
    assert.is_true(vim.list_contains(names, "marks.all"))
  end)
end)
