describe("peekstack.commands", function()
  local commands = require("peekstack.commands")
  local config = require("peekstack.config")
  local peekstack = require("peekstack")
  local persist = require("peekstack.persist")
  local original_list_sessions = nil
  local original_delete_session = nil
  local original_select = nil
  local original_notify = nil
  local original_strftime = nil

  before_each(function()
    config.setup({})
    commands._reset()
    original_list_sessions = persist.list_sessions
    original_delete_session = persist.delete_session
    original_select = vim.ui.select
    original_notify = vim.notify
    original_strftime = vim.fn.strftime
  end)

  after_each(function()
    config.setup({})
    if original_list_sessions then
      persist.list_sessions = original_list_sessions
    end
    if original_delete_session then
      persist.delete_session = original_delete_session
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

  it("filters session completion by ArgLead prefix", function()
    persist.list_sessions = function()
      return {
        alpha = { items = {}, meta = { created_at = 1, updated_at = 1 } },
        alpine = { items = {}, meta = { created_at = 1, updated_at = 1 } },
        beta = { items = {}, meta = { created_at = 1, updated_at = 1 } },
      }
    end

    commands.setup()
    local names = vim.fn.getcompletion("PeekstackRestoreSession al", "cmdline")
    table.sort(names)

    assert.same({ "alpha", "alpine" }, names)
  end)

  it("filters quick peek completion by ArgLead prefix", function()
    peekstack.setup({})
    local names = vim.fn.getcompletion("PeekstackQuickPeek lsp.d", "cmdline")

    assert.is_true(#names > 0)
    for _, name in ipairs(names) do
      assert.is_true(vim.startswith(name, "lsp.d"))
    end
    assert.is_true(vim.list_contains(names, "lsp.definition"))
    assert.is_true(vim.list_contains(names, "lsp.declaration"))
    assert.is_false(vim.list_contains(names, "lsp.references"))
  end)

  it("prompts to select a session when delete is invoked without a name", function()
    local deleted = nil
    local select_items = nil
    persist.list_sessions = function(opts)
      assert.is_truthy(opts)
      assert.is_truthy(opts.on_done)
      opts.on_done({
        beta = { items = {}, meta = { created_at = 1, updated_at = 1 } },
        alpha = { items = {}, meta = { created_at = 1, updated_at = 1 } },
      })
      return {}
    end
    persist.delete_session = function(name)
      deleted = name
    end

    vim.ui.select = function(items, opts, on_choice)
      if opts.prompt == "Delete session" then
        select_items = vim.deepcopy(items)
        on_choice("beta")
        return
      end
      on_choice("Yes")
    end

    commands.setup()
    vim.api.nvim_cmd({ cmd = "PeekstackDeleteSession" }, {})

    assert.same({ "alpha", "beta" }, select_items)
    assert.equals("beta", deleted)
  end)

  it("notifies when no sessions exist on nameless delete", function()
    local deleted = false
    local messages = {}
    persist.list_sessions = function(opts)
      opts.on_done({})
      return {}
    end
    persist.delete_session = function()
      deleted = true
    end
    vim.notify = function(msg)
      table.insert(messages, msg)
    end

    commands.setup()
    vim.api.nvim_cmd({ cmd = "PeekstackDeleteSession" }, {})

    assert.is_true(vim.list_contains(messages, "[peekstack] No saved sessions"))
    assert.is_false(deleted)
  end)

  it("confirms before deleting a named session", function()
    local deleted = nil
    local prompt = nil
    persist.delete_session = function(name)
      deleted = name
    end
    vim.ui.select = function(_items, opts, on_choice)
      prompt = opts.prompt
      on_choice("Yes")
    end

    commands.setup()
    vim.api.nvim_cmd({ cmd = "PeekstackDeleteSession", args = { "alpha" } }, {})

    assert.equals("Delete session 'alpha'?", prompt)
    assert.equals("alpha", deleted)
  end)

  it("does not delete a named session when confirmation is declined", function()
    local deleted = false
    persist.delete_session = function()
      deleted = true
    end
    vim.ui.select = function(_items, _opts, on_choice)
      on_choice("No")
    end

    commands.setup()
    vim.api.nvim_cmd({ cmd = "PeekstackDeleteSession", args = { "alpha" } }, {})

    assert.is_false(deleted)
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

  it("sorts sessions in list command", function()
    local first_items = nil
    persist.list_sessions = function(opts)
      assert.is_truthy(opts)
      assert.is_truthy(opts.on_done)
      opts.on_done({
        zeta = { items = {}, meta = { created_at = 1, updated_at = 1 } },
        alpha = { items = {}, meta = { created_at = 1, updated_at = 1 } },
      })
      return {}
    end

    vim.ui.select = function(items, opts, on_choice)
      if opts.prompt == "Select a session" then
        first_items = vim.deepcopy(items)
      end
      on_choice(nil)
    end

    commands.setup()
    vim.api.nvim_cmd({ cmd = "PeekstackListSessions" }, {})

    assert.same({ "alpha", "zeta" }, first_items)
  end)

  it("notifies when list sessions is invoked while persist is disabled", function()
    config.setup({ persist = { enabled = false } })

    local messages = {}
    vim.notify = function(msg)
      table.insert(messages, msg)
    end

    commands.setup()
    vim.api.nvim_cmd({ cmd = "PeekstackListSessions" }, {})

    assert.is_true(vim.list_contains(messages, "[peekstack] peekstack.persist is disabled"))
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

  it("uses registered providers for quick peek completion", function()
    peekstack.setup({})
    local names = vim.fn.getcompletion("PeekstackQuickPeek ", "cmdline")

    assert.is_true(vim.list_contains(names, "lsp.declaration"))
    assert.is_true(vim.list_contains(names, "lsp.symbols_document"))
    assert.is_true(vim.list_contains(names, "diagnostics.in_buffer"))
    assert.is_false(vim.list_contains(names, "marks.buffer"))
    assert.is_false(vim.list_contains(names, "marks.global"))
    assert.is_false(vim.list_contains(names, "marks.all"))
  end)

  it("reflects provider registration changes in quick peek completion", function()
    peekstack.setup({
      providers = {
        marks = {
          enable = true,
        },
      },
    })

    local names = vim.fn.getcompletion("PeekstackQuickPeek ", "cmdline")
    assert.is_true(vim.list_contains(names, "marks.buffer"))
    assert.is_true(vim.list_contains(names, "marks.global"))
    assert.is_true(vim.list_contains(names, "marks.all"))

    peekstack.register_provider("custom.test", function(_ctx, cb)
      cb({})
    end)

    names = vim.fn.getcompletion("PeekstackQuickPeek ", "cmdline")
    assert.is_true(vim.list_contains(names, "custom.test"))
  end)
end)
