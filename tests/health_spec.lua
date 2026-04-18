describe("peekstack.health", function()
  local health = require("peekstack.health")
  local config = require("peekstack.config")

  local original_health_start
  local original_health_ok
  local original_health_warn
  local original_health_error
  local original_health_info
  local original_executable
  local original_has
  local original_get_parser

  ---@type string[]
  local messages

  before_each(function()
    messages = {}
    original_health_start = vim.health.start
    original_health_ok = vim.health.ok
    original_health_warn = vim.health.warn
    original_health_error = vim.health.error
    original_health_info = vim.health.info
    original_executable = vim.fn.executable
    original_has = vim.fn.has
    original_get_parser = vim.treesitter.get_parser

    vim.health.start = function() end
    vim.health.ok = function(msg)
      table.insert(messages, "ok:" .. msg)
    end
    vim.health.warn = function(msg)
      table.insert(messages, "warn:" .. msg)
    end
    vim.health.error = function(msg)
      table.insert(messages, "error:" .. msg)
    end
    vim.health.info = function(msg)
      table.insert(messages, "info:" .. msg)
    end
  end)

  after_each(function()
    vim.health.start = original_health_start
    vim.health.ok = original_health_ok
    vim.health.warn = original_health_warn
    vim.health.error = original_health_error
    vim.health.info = original_health_info
    vim.fn.executable = original_executable
    vim.fn.has = original_has
    vim.treesitter.get_parser = original_get_parser
    config.setup({})
  end)

  it("reports ok for nvim version and rg when available", function()
    vim.fn.has = function()
      return 1
    end
    vim.fn.executable = function()
      return 1
    end
    config.setup({})

    health.check()

    assert.is_true(vim.list_contains(messages, "ok:nvim >= 0.12"))
    assert.is_true(vim.list_contains(messages, "ok:rg available"))
  end)

  it("warns when rg is not available", function()
    vim.fn.has = function()
      return 1
    end
    vim.fn.executable = function()
      return 0
    end
    config.setup({})

    health.check()

    local found = false
    for _, msg in ipairs(messages) do
      if msg:find("warn:rg not found") then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it("warns when configured picker backend is not installed", function()
    vim.fn.has = function()
      return 1
    end
    vim.fn.executable = function()
      return 1
    end
    config.setup({ picker = { backend = "telescope" } })

    health.check()

    local found = false
    for _, msg in ipairs(messages) do
      if msg:find("warn:") and msg:find("telescope") and msg:find("not installed") then
        found = true
      end
    end
    assert.is_true(found)
  end)

  it("reports persist status when enabled inside a git repo", function()
    vim.fn.has = function()
      return 1
    end
    vim.fn.executable = function()
      return 1
    end
    config.setup({ persist = { enabled = true } })

    health.check()

    local found_persist = false
    for _, msg in ipairs(messages) do
      if msg:find("persist") then
        found_persist = true
      end
    end
    assert.is_true(found_persist)
  end)

  it("reports tree-sitter info when context is enabled without a parser", function()
    vim.fn.has = function()
      return 1
    end
    vim.fn.executable = function()
      return 1
    end
    vim.treesitter.get_parser = function()
      return nil
    end
    config.setup({
      ui = {
        title = {
          context = {
            enabled = true,
          },
        },
      },
    })

    health.check()

    assert.is_true(
      vim.list_contains(messages, "info:tree-sitter context enabled but no parser for the current buffer filetype")
    )
  end)
end)
