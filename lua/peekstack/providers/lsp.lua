local location = require("peekstack.core.location")

local M = {}

---@param ctx PeekstackProviderContext
---@param method string
---@param provider string
---@param params_modifier nil|fun(params: table)
---@param cb fun(locations: PeekstackLocation[])
local function request(ctx, method, provider, params_modifier, cb)
  local bufnr = ctx.bufnr
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = method })
  if not clients or vim.tbl_isempty(clients) then
    vim.notify("No LSP clients attached", vim.log.levels.WARN)
    return
  end

  local all_locations = {}
  local remaining = #clients

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
        local locs = location.list_from_lsp(result, provider)
        vim.list_extend(all_locations, locs)
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
---@return fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))
local function create_provider(method, provider, params_modifier)
  return function(ctx, cb)
    request(ctx, method, provider, params_modifier, cb)
  end
end

M.definition = create_provider("textDocument/definition", "lsp.definition")
M.implementation = create_provider("textDocument/implementation", "lsp.implementation")
M.type_definition = create_provider("textDocument/typeDefinition", "lsp.type_definition")
M.declaration = create_provider("textDocument/declaration", "lsp.declaration")
M.references = create_provider("textDocument/references", "lsp.references", function(params)
  params.context = { includeDeclaration = false }
end)

return M
