local location = require("peekstack.core.location")

local M = {}

---@alias PeekstackLspResultMapper fun(result: any, provider: string, ctx: PeekstackProviderContext): PeekstackLocation[]

---@param symbol table
---@param uri string
---@param provider string
---@param out PeekstackLocation[]
local function append_document_symbol(symbol, uri, provider, out)
  if type(symbol) ~= "table" then
    return
  end

  local range = symbol.selectionRange or symbol.range
  local start_pos = range and range.start
  local end_pos = range and range["end"]
  if start_pos and end_pos then
    local text
    if type(symbol.name) == "string" and symbol.name ~= "" then
      text = symbol.name
    elseif type(symbol.detail) == "string" and symbol.detail ~= "" then
      text = symbol.detail
    end

    table.insert(out, {
      uri = uri,
      range = range,
      text = text,
      kind = symbol.kind,
      provider = provider,
    })
  end

  if vim.islist(symbol.children) then
    for _, child in ipairs(symbol.children) do
      append_document_symbol(child, uri, provider, out)
    end
  end
end

---@param result any
---@param provider string
---@param _ctx PeekstackProviderContext
---@return PeekstackLocation[]
local function default_result_mapper(result, provider, _ctx)
  return location.list_from_lsp(result, provider)
end

---@param result any
---@param provider string
---@param ctx PeekstackProviderContext
---@return PeekstackLocation[]
local function document_symbol_result_mapper(result, provider, ctx)
  local items = {}
  if not result then
    return items
  end

  local results = vim.islist(result) and result or { result }

  local uri
  if ctx.bufnr and vim.api.nvim_buf_is_valid(ctx.bufnr) then
    uri = vim.uri_from_bufnr(ctx.bufnr)
  end

  for _, symbol in ipairs(results) do
    if type(symbol) == "table" and symbol.location then
      local loc = location.normalize(symbol.location, provider)
      if loc then
        if type(symbol.name) == "string" and symbol.name ~= "" then
          loc.text = symbol.name
        end
        if type(symbol.kind) == "number" then
          loc.kind = symbol.kind
        end
        table.insert(items, loc)
      end
    elseif uri then
      append_document_symbol(symbol, uri, provider, items)
    end
  end

  return items
end

---@param ctx PeekstackProviderContext
---@param method string
---@param provider string
---@param params_modifier nil|fun(params: table)
---@param result_mapper nil|PeekstackLspResultMapper
---@param cb fun(locations: PeekstackLocation[])
local function request(ctx, method, provider, params_modifier, result_mapper, cb)
  local bufnr = ctx.bufnr
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = method })
  if not clients or vim.tbl_isempty(clients) then
    vim.notify("No LSP clients attached", vim.log.levels.WARN)
    return
  end

  local all_locations = {}
  local remaining = #clients
  local mapper = result_mapper or default_result_mapper

  for _, client in ipairs(clients) do
    local params = {
      textDocument = vim.lsp.util.make_text_document_params(bufnr),
      position = {
        line = ctx.position.line,
        character = ctx.position.character,
      },
    }
    if params_modifier then
      params_modifier(params)
    end
    client:request(method, params, function(err, result)
      if not err and result then
        local ok, locs = pcall(mapper, result, provider, ctx)
        if ok and type(locs) == "table" then
          vim.list_extend(all_locations, locs)
        end
      end
      remaining = remaining - 1
      if remaining == 0 then
        cb(all_locations)
      end
    end, bufnr)
  end
end

---@param method string
---@param provider string
---@param params_modifier nil|fun(params: table)
---@param result_mapper nil|PeekstackLspResultMapper
---@return fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))
local function create_provider(method, provider, params_modifier, result_mapper)
  return function(ctx, cb)
    request(ctx, method, provider, params_modifier, result_mapper, cb)
  end
end

M.definition = create_provider("textDocument/definition", "lsp.definition")
M.implementation = create_provider("textDocument/implementation", "lsp.implementation")
M.type_definition = create_provider("textDocument/typeDefinition", "lsp.type_definition")
M.declaration = create_provider("textDocument/declaration", "lsp.declaration")
M.references = create_provider("textDocument/references", "lsp.references", function(params)
  params.context = { includeDeclaration = false }
end)
M.symbols_document = create_provider("textDocument/documentSymbol", "lsp.symbols_document", function(params)
  params.position = nil
end, document_symbol_result_mapper)

return M
