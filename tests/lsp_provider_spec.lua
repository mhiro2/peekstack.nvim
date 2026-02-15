local lsp_provider = require("peekstack.providers.lsp")

describe("peekstack.providers.lsp", function()
  local original_get_clients
  local original_notify
  local notifications

  local function make_ctx()
    local winid = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_get_current_buf()
    return {
      winid = winid,
      bufnr = bufnr,
      source_bufnr = nil,
      popup_id = nil,
      buffer_mode = nil,
      line_offset = 0,
      position = { line = 0, character = 0 },
      root_winid = winid,
      from_popup = false,
    }
  end

  before_each(function()
    original_get_clients = vim.lsp.get_clients
    original_notify = vim.notify
    notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.lsp.get_clients = original_get_clients
    vim.notify = original_notify
  end)

  it("maps DocumentSymbol results with hierarchy flattening", function()
    vim.lsp.get_clients = function(opts)
      assert.equals("textDocument/documentSymbol", opts.method)
      return {
        {
          request = function(_, method, params, handler, _bufnr)
            assert.equals("textDocument/documentSymbol", method)
            assert.is_nil(params.position)
            assert.is_table(params.textDocument)

            handler(nil, {
              {
                name = "Parent",
                detail = "class",
                kind = 5,
                range = {
                  start = { line = 0, character = 0 },
                  ["end"] = { line = 20, character = 0 },
                },
                selectionRange = {
                  start = { line = 1, character = 2 },
                  ["end"] = { line = 1, character = 8 },
                },
                children = {
                  {
                    name = "Child",
                    kind = 6,
                    range = {
                      start = { line = 3, character = 1 },
                      ["end"] = { line = 3, character = 5 },
                    },
                  },
                },
              },
              { name = "BrokenWithoutRange" },
            })
          end,
        },
      }
    end

    local received
    local ctx = make_ctx()
    lsp_provider.symbols_document(ctx, function(locations)
      received = locations
    end)

    assert.is_table(received)
    assert.equals(2, #received)
    assert.equals(vim.uri_from_bufnr(ctx.bufnr), received[1].uri)
    assert.equals(1, received[1].range.start.line)
    assert.equals(2, received[1].range.start.character)
    assert.equals("Parent", received[1].text)
    assert.equals(5, received[1].kind)
    assert.equals("lsp.symbols_document", received[1].provider)

    assert.equals(3, received[2].range.start.line)
    assert.equals(1, received[2].range.start.character)
    assert.equals("Child", received[2].text)
    assert.equals(6, received[2].kind)
    assert.equals("lsp.symbols_document", received[2].provider)
  end)

  it("maps SymbolInformation results", function()
    vim.lsp.get_clients = function(opts)
      assert.equals("textDocument/documentSymbol", opts.method)
      return {
        {
          request = function(_, _method, _params, handler, _bufnr)
            handler(nil, {
              {
                name = "GlobalFn",
                kind = 12,
                location = {
                  uri = "file:///tmp/symbol.lua",
                  range = {
                    start = { line = 9, character = 4 },
                    ["end"] = { line = 9, character = 12 },
                  },
                },
              },
              {
                name = "Invalid",
                location = {},
              },
            })
          end,
        },
      }
    end

    local received
    lsp_provider.symbols_document(make_ctx(), function(locations)
      received = locations
    end)

    assert.is_table(received)
    assert.equals(1, #received)
    assert.equals("file:///tmp/symbol.lua", received[1].uri)
    assert.equals(9, received[1].range.start.line)
    assert.equals(4, received[1].range.start.character)
    assert.equals("GlobalFn", received[1].text)
    assert.equals(12, received[1].kind)
    assert.equals("lsp.symbols_document", received[1].provider)
  end)

  it("warns when no lsp clients are attached", function()
    vim.lsp.get_clients = function(_opts)
      return {}
    end

    local called = false
    lsp_provider.symbols_document(make_ctx(), function(_locations)
      called = true
    end)

    assert.is_false(called)
    local found = false
    for _, item in ipairs(notifications) do
      if item.msg == "No LSP clients attached" then
        found = true
        break
      end
    end
    assert.is_true(found)
  end)
end)
