describe("peekstack.commands", function()
  local commands = require("peekstack.commands")
  local config = require("peekstack.config")
  local persist = require("peekstack.persist")
  local original_list_sessions = nil
  local original_select = nil
  local original_notify = nil
  local original_strftime = nil

  before_each(function()
    config.setup({})
    commands._reset()
    original_list_sessions = persist.list_sessions
    original_select = vim.ui.select
    original_notify = vim.notify
    original_strftime = vim.fn.strftime
  end)

  after_each(function()
    config.setup({})
    if original_list_sessions then
      persist.list_sessions = original_list_sessions
    end
    if original_select then
      vim.ui.select = original_select
    end
    if original_notify then
      vim.notify = original_notify
    end
    if original_strftime then
      vim.fn.strftime = original_strftime
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

  it("notifies when list sessions is invoked while persist is disabled", function()
    config.setup({ persist = { enabled = false } })

    local messages = {}
    vim.notify = function(msg)
      table.insert(messages, msg)
    end

    commands.setup()
    vim.api.nvim_cmd({ cmd = "PeekstackListSessions" }, {})

    assert.is_true(vim.list_contains(messages, "peekstack.persist is disabled"))
  end)

  it("formats session updated_at with vim.fn.strftime", function()
    local prompts = {}
    local strftime_calls = {}

    persist.list_sessions = function(opts)
      assert.is_truthy(opts)
      assert.is_truthy(opts.on_done)
      opts.on_done({
        alpha = {
          items = {},
          meta = { updated_at = 123 },
        },
      })
      return {}
    end

    vim.fn.strftime = function(fmt, ts)
      table.insert(strftime_calls, { fmt = fmt, ts = ts })
      return "formatted-time"
    end

    vim.ui.select = function(_items, opts, on_choice)
      table.insert(prompts, opts.prompt)
      if opts.prompt == "Select a session" then
        on_choice("alpha")
        return
      end
      on_choice("Info only")
    end

    commands.setup()
    vim.api.nvim_cmd({ cmd = "PeekstackListSessions" }, {})

    assert.equals(1, #strftime_calls)
    assert.equals("%Y-%m-%d %H:%M:%S", strftime_calls[1].fmt)
    assert.equals(123, strftime_calls[1].ts)
    assert.equals("alpha: 0 items (updated: formatted-time)", prompts[2])
  end)

  it("includes extended providers in quick peek completion", function()
    commands.setup()
    local names = vim.fn.getcompletion("PeekstackQuickPeek ", "cmdline")

    assert.is_true(vim.list_contains(names, "lsp.declaration"))
    assert.is_true(vim.list_contains(names, "lsp.symbols_document"))
    assert.is_true(vim.list_contains(names, "diagnostics.in_buffer"))
    assert.is_true(vim.list_contains(names, "marks.buffer"))
    assert.is_true(vim.list_contains(names, "marks.global"))
    assert.is_true(vim.list_contains(names, "marks.all"))
  end)
end)
