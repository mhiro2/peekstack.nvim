local peekstack = require("peekstack")
local context = require("peekstack.core.context")
local stack = require("peekstack.core.stack")
local lsp_provider = require("peekstack.providers.lsp")

-- "target" starts at byte 10 / UTF-16 4 / UTF-32 4.
local CJK_LINE = "日本語 target"
-- "target" starts at byte 5 / UTF-16 3 / UTF-32 2.
local EMOJI_LINE = "😀 target"

describe("lsp offset encoding", function()
  local original_get_clients
  local tmpdir
  local fname
  local uri

  ---@param encoding string
  ---@param response? fun(params: table): any
  ---@param sent? table[]
  ---@return table
  local function make_client(encoding, response, sent)
    return {
      offset_encoding = encoding,
      request = function(_, _method, params, handler, _bufnr)
        if sent then
          table.insert(sent, { encoding = encoding, params = params })
        end
        handler(nil, response and response(params) or nil)
      end,
    }
  end

  ---@param line integer
  ---@param character integer
  ---@param target_uri? string
  ---@return table
  local function lsp_location(line, character, target_uri)
    return {
      uri = target_uri or uri,
      range = {
        start = { line = line, character = character },
        ["end"] = { line = line, character = character + 6 },
      },
    }
  end

  ---@param line integer
  ---@param col integer
  ---@return PeekstackProviderContext
  local function ctx_at(line, col)
    vim.api.nvim_win_set_cursor(0, { line + 1, col })
    return context.current()
  end

  ---@param provider fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))
  ---@param ctx PeekstackProviderContext
  ---@return PeekstackLocation[]
  local function collect(provider, ctx)
    local received
    provider(ctx, function(locations)
      received = locations
    end)
    assert.is_table(received)
    return received
  end

  before_each(function()
    original_get_clients = vim.lsp.get_clients
    stack._reset()
    peekstack.setup({})
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    fname = tmpdir .. "/source.txt"
    vim.fn.writefile({ CJK_LINE, EMOJI_LINE, "plain target" }, fname)
    vim.cmd.edit(vim.fn.fnameescape(fname))
    uri = vim.uri_from_bufnr(0)
  end)

  after_each(function()
    vim.lsp.get_clients = original_get_clients
    local s = stack.current_stack()
    for i = #s.popups, 1, -1 do
      stack.close(s.popups[i].id)
    end
    stack._reset()
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(tmpdir, "rf")
  end)

  it("sends the cursor column in each client's offset encoding", function()
    local sent = {}
    vim.lsp.get_clients = function()
      return {
        make_client("utf-8", nil, sent),
        make_client("utf-16", nil, sent),
        make_client("utf-32", nil, sent),
      }
    end

    collect(lsp_provider.definition, ctx_at(0, 10))
    collect(lsp_provider.definition, ctx_at(1, 5))

    local by_encoding = {}
    for _, item in ipairs(sent) do
      by_encoding[item.encoding] = by_encoding[item.encoding] or {}
      table.insert(by_encoding[item.encoding], item.params.position.character)
    end
    assert.same({ 10, 5 }, by_encoding["utf-8"])
    assert.same({ 4, 3 }, by_encoding["utf-16"])
    assert.same({ 4, 2 }, by_encoding["utf-32"])
  end)

  it("converts response columns from each client's encoding to bytes", function()
    vim.lsp.get_clients = function()
      return {
        make_client("utf-8", function()
          return lsp_location(0, 10)
        end),
        make_client("utf-16", function()
          return { lsp_location(0, 4), lsp_location(1, 3) }
        end),
        make_client("utf-32", function()
          return lsp_location(1, 2)
        end),
      }
    end

    local locations = collect(lsp_provider.references, ctx_at(2, 0))

    assert.equals(4, #locations)
    for _, loc in ipairs(locations) do
      local expected = loc.range.start.line == 0 and 10 or 5
      assert.equals(expected, loc.range.start.character)
      assert.equals(expected + 6, loc.range["end"].character)
    end
  end)

  it("reads unloaded files from disk to convert columns", function()
    local other = tmpdir .. "/other.txt"
    vim.fn.writefile({ "x", EMOJI_LINE }, other)
    local other_uri = vim.uri_from_fname(other)
    vim.lsp.get_clients = function()
      return {
        make_client("utf-16", function()
          return lsp_location(1, 3, other_uri)
        end),
      }
    end

    local locations = collect(lsp_provider.definition, ctx_at(2, 0))

    assert.equals(1, #locations)
    assert.equals(5, locations[1].range.start.character)
    assert.equals(-1, vim.fn.bufnr(other))
  end)

  it("ignores a UTF-8 BOM and CRLF line endings in unloaded files", function()
    local other = tmpdir .. "/bom.txt"
    local file = assert(io.open(other, "wb"))
    file:write("\239\187\191" .. CJK_LINE .. "\r\n" .. EMOJI_LINE .. "\r\n")
    file:close()
    local other_uri = vim.uri_from_fname(other)
    vim.lsp.get_clients = function()
      return {
        make_client("utf-16", function()
          return {
            uri = other_uri,
            range = {
              start = { line = 0, character = 4 },
              -- Past the end of the line: clamps to the line length, not into the CR.
              ["end"] = { line = 1, character = 99 },
            },
          }
        end),
      }
    end

    local locations = collect(lsp_provider.definition, ctx_at(2, 0))

    assert.equals(1, #locations)
    assert.same({ line = 0, character = 10 }, locations[1].range.start)
    assert.same({ line = 1, character = #EMOJI_LINE }, locations[1].range["end"])
  end)

  it("uses unsaved text of a loaded buffer reached through a symlinked path", function()
    local link = tmpdir .. "/link.txt"
    assert(vim.uv.fs_symlink(fname, link))
    -- Disk still has CJK_LINE on line 0; the buffer now has the emoji there.
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { EMOJI_LINE })
    vim.lsp.get_clients = function()
      return {
        make_client("utf-16", function()
          return lsp_location(0, 3, vim.uri_from_fname(link))
        end),
      }
    end

    local locations = collect(lsp_provider.definition, ctx_at(2, 0))

    assert.equals(1, #locations)
    assert.equals(5, locations[1].range.start.character)
  end)

  it("keeps other clients' results when one response cannot be converted", function()
    vim.lsp.get_clients = function()
      return {
        make_client("utf-16", function()
          return { uri = uri, range = { start = { line = 0, character = 4 } } }
        end),
        make_client("utf-16", function()
          -- A non-string URI makes the conversion itself throw.
          return { uri = 42, range = lsp_location(0, 4).range }
        end),
        make_client("utf-16", function()
          return lsp_location(1, 3)
        end),
      }
    end

    local locations = collect(lsp_provider.definition, ctx_at(2, 0))

    assert.equals(2, #locations)
    assert.same({ line = 0, character = 10 }, locations[1].range.start)
    assert.same({ line = 0, character = 10 }, locations[1].range["end"])
    assert.same({ line = 1, character = 5 }, locations[2].range.start)
  end)

  it("converts a LocationLink's targetSelectionRange", function()
    vim.lsp.get_clients = function()
      return {
        make_client("utf-16", function()
          return {
            {
              targetUri = uri,
              targetRange = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 9 } },
              targetSelectionRange = { start = { line = 1, character = 3 }, ["end"] = { line = 1, character = 9 } },
            },
          }
        end),
      }
    end

    local locations = collect(lsp_provider.definition, ctx_at(2, 0))

    assert.equals(1, #locations)
    assert.same({ line = 1, character = 5 }, locations[1].range.start)
    assert.same({ line = 1, character = 11 }, locations[1].range["end"])
  end)

  it("converts document symbol ranges to bytes", function()
    vim.lsp.get_clients = function()
      return {
        make_client("utf-16", function()
          return {
            {
              name = "target",
              kind = 13,
              range = lsp_location(0, 0).range,
              selectionRange = lsp_location(0, 4).range,
            },
          }
        end),
      }
    end

    local locations = collect(lsp_provider.symbols_document, ctx_at(2, 0))

    assert.equals(1, #locations)
    assert.equals(10, locations[1].range.start.character)
    assert.equals(16, locations[1].range["end"].character)
  end)

  it("keeps a multibyte target that differs from the cursor only in LSP units", function()
    -- The cursor sits on byte 3 ("本") and the target on UTF-16 column 3 (the
    -- space at byte 9). Comparing the raw columns would drop the target.
    vim.lsp.get_clients = function()
      return {
        make_client("utf-16", function()
          return {
            uri = uri,
            range = {
              start = { line = 0, character = 3 },
              ["end"] = { line = 0, character = 3 },
            },
          }
        end),
      }
    end

    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    peekstack.peek.definition()

    local popups = stack.list()
    assert.equals(1, #popups)
    assert.equals(9, popups[1].location.range.start.character)
  end)

  it("opens the popup on the byte column and requests from a copy popup in client units", function()
    local sent = {}
    vim.lsp.get_clients = function()
      return {
        make_client("utf-16", function(params)
          if params.position.line == 2 then
            return lsp_location(0, 4)
          end
          return lsp_location(1, 3)
        end, sent),
      }
    end

    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    peekstack.peek.definition({ buffer_mode = "copy" })

    local popups = stack.list()
    assert.equals(1, #popups)
    local popup = popups[1]
    assert.equals("copy", popup.buffer_mode)
    assert.same({ 1, 10 }, vim.api.nvim_win_get_cursor(popup.winid))

    vim.api.nvim_set_current_win(popup.winid)
    peekstack.peek.definition()

    assert.equals(0, sent[2].params.position.line)
    assert.equals(4, sent[2].params.position.character)
    popups = stack.list()
    assert.equals(2, #popups)
    assert.same({ 2, 5 }, vim.api.nvim_win_get_cursor(popups[2].winid))
  end)
end)
