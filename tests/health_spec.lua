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

    local found = false
    for _, msg in ipairs(messages) do
      if msg:find("info:tree-sitter context enabled but no parser", 1, true) then
        found = true
      end
    end
    assert.is_true(found)
  end)

  ---@param needle string
  local function find_message(needle)
    for _, msg in ipairs(messages) do
      if msg:find(needle, 1, true) then
        return msg
      end
    end
    return nil
  end

  it("lists enabled providers", function()
    vim.fn.has = function()
      return 1
    end
    vim.fn.executable = function()
      return 1
    end
    config.setup({
      providers = {
        marks = { enable = false },
      },
    })

    health.check()

    local enabled = find_message("providers enabled:")
    assert.is_not_nil(enabled)
    assert.is_not_nil(enabled:find("lsp"))
    assert.is_not_nil(enabled:find("diagnostics"))
    assert.is_not_nil(enabled:find("file"))
    assert.is_not_nil(enabled:find("grep"))
    assert.is_nil(enabled:find("marks"))
    assert.is_not_nil(find_message("provider 'marks' disabled"))
  end)

  it("reports persist storage path when persist is enabled", function()
    vim.fn.has = function()
      return 1
    end
    vim.fn.executable = function()
      return 1
    end
    config.setup({ persist = { enabled = true } })

    health.check()

    assert.is_not_nil(find_message("storage path:"))
  end)

  it("reports quick_peek and inline_preview close events", function()
    vim.fn.has = function()
      return 1
    end
    vim.fn.executable = function()
      return 1
    end
    config.setup({
      ui = {
        quick_peek = { close_events = { "BufLeave" } },
        inline_preview = { enabled = true, close_events = { "WinLeave", "InsertEnter" } },
      },
    })

    health.check()

    local quick = find_message("quick_peek close_events:")
    assert.is_not_nil(quick)
    assert.is_not_nil(quick:find("BufLeave"))

    local inline = find_message("inline_preview close_events:")
    assert.is_not_nil(inline)
    assert.is_not_nil(inline:find("WinLeave"))
    assert.is_not_nil(inline:find("InsertEnter"))
  end)

  it("reports picker preview_lines configuration", function()
    vim.fn.has = function()
      return 1
    end
    vim.fn.executable = function()
      return 1
    end
    config.setup({ picker = { builtin = { preview_lines = 3 } } })

    health.check()

    assert.is_not_nil(find_message("picker.builtin.preview_lines = 3"))
  end)

  it("does not error when persist.auto is not a table", function()
    vim.fn.has = function()
      return 1
    end
    vim.fn.executable = function()
      return 1
    end
    config.setup({
      persist = {
        enabled = true,
        auto = true,
      },
    })

    assert.has_no_error(function()
      health.check()
    end)
    assert.is_not_nil(find_message("auto persist disabled"))
  end)

  it("warns when auto persist is enabled outside a git repository", function()
    vim.fn.has = function()
      return 1
    end
    vim.fn.executable = function()
      return 1
    end
    local fs = require("peekstack.util.fs")
    local original_repo_root = fs.repo_root
    fs.repo_root = function()
      return nil
    end
    config.setup({
      persist = {
        enabled = true,
        auto = { enabled = true },
      },
    })

    health.check()

    fs.repo_root = original_repo_root

    local found = false
    for _, msg in ipairs(messages) do
      if msg:find("warn:auto persist enabled", 1, true) and msg:find("inactive outside git repository", 1, true) then
        found = true
      end
    end
    assert.is_true(found)
  end)
end)
