local notify = require("peekstack.util.notify")
local registry = require("peekstack.registry")

local M = {}

---@param name string?
---@return boolean
local function is_lsp_provider(name)
  return type(name) == "string" and name:match("^lsp%.") ~= nil
end

---@return PeekstackPicker
local function pick_backend()
  local config = require("peekstack.config")
  local backend = config.get().picker.backend
  return registry.get_picker(backend) or registry.get_picker("builtin")
end

---Normalize location and set provider from opts if needed.
---@param loc table
---@param opts? table
---@return PeekstackLocation?
local function prepare_location(loc, opts)
  local location = require("peekstack.core.location")
  local provider = opts and opts.provider

  if loc.provider == nil and provider then
    loc.provider = provider
  end

  local normalized = location.normalize(loc, loc.provider)
  if normalized then
    return normalized
  end

  notify.warn("Invalid location payload: expected uri/range")
  return nil
end

---@param loc table
---@param opts? table
function M.peek_location(loc, opts)
  if not loc then
    return
  end

  local normalized = prepare_location(loc, opts)
  if not normalized then
    return
  end

  local mode = opts and opts.mode
  if mode == "inline" then
    local cfg = require("peekstack.config").get()
    if cfg.ui.inline_preview and cfg.ui.inline_preview.enabled then
      require("peekstack.ui.inline_preview").open(normalized, opts)
      return
    end
    mode = nil
  end

  local stack = require("peekstack.core.stack")
  if mode == "quick" then
    stack.push(normalized, vim.tbl_extend("force", opts, { stack = false }))
    return
  end

  stack.push(normalized, opts)
end

---@param locations? PeekstackLocation[]
---@param opts? table
function M.peek_locations(locations, opts)
  if not locations or #locations == 0 then
    notify.info("No locations")
    return
  end
  if #locations == 1 then
    M.peek_location(locations[1], opts)
    return
  end

  local picker = pick_backend()
  picker.pick(locations, opts or {}, function(choice)
    if choice then
      M.peek_location(choice, opts)
    end
  end)
end

---@param provider string
---@param opts? table
local function peek_by_provider(provider, opts)
  local fn = registry.get_provider(provider)
  if not fn then
    notify.warn("Unknown provider: " .. tostring(provider))
    return
  end

  local context = require("peekstack.core.context")
  local ctx = context.current()
  local merged = vim.tbl_extend("force", opts or {}, { provider = provider })
  fn(ctx, function(locations)
    local filtered = locations or {}
    if is_lsp_provider(provider) and locations and #locations > 0 then
      local location_mod = require("peekstack.core.location")
      local pos = ctx.position or {}
      local uri = nil
      if ctx.bufnr and vim.api.nvim_buf_is_valid(ctx.bufnr) then
        uri = vim.uri_from_bufnr(ctx.bufnr)
      end
      if uri and pos.line ~= nil and pos.character ~= nil then
        local realpath_cache = {}
        filtered = {}
        for _, loc in ipairs(locations) do
          local normalized = location_mod.normalize(loc, provider)
          if
            normalized
            and not location_mod.is_same_position(normalized, uri, pos.line, pos.character, {
              realpath_cache = realpath_cache,
            })
          then
            table.insert(filtered, normalized)
          end
        end
      end
    end
    M.peek_locations(filtered, merged)
  end)
end

---@class PeekstackPeekMethods
---@field definition fun(opts?: table)
---@field implementation fun(opts?: table)
---@field references fun(opts?: table)
---@field type_definition fun(opts?: table)
---@field declaration fun(opts?: table)
---@field symbols_document fun(opts?: table)
---@field diagnostics_cursor fun(opts?: table)
---@field diagnostics_buffer fun(opts?: table)
---@field file_under_cursor fun(opts?: table)
---@field grep fun(opts?: table)
---@field marks_buffer fun(opts?: table)
---@field marks_global fun(opts?: table)
---@field marks_all fun(opts?: table)

---@alias PeekstackPeekCallable fun(provider: string, opts?: table)

---@type PeekstackPeekMethods|PeekstackPeekCallable
M.peek = setmetatable({
  definition = function(opts)
    return peek_by_provider("lsp.definition", opts)
  end,
  implementation = function(opts)
    return peek_by_provider("lsp.implementation", opts)
  end,
  references = function(opts)
    return peek_by_provider("lsp.references", opts)
  end,
  type_definition = function(opts)
    return peek_by_provider("lsp.type_definition", opts)
  end,
  declaration = function(opts)
    return peek_by_provider("lsp.declaration", opts)
  end,
  symbols_document = function(opts)
    return peek_by_provider("lsp.symbols_document", opts)
  end,
  diagnostics_cursor = function(opts)
    return peek_by_provider("diagnostics.under_cursor", opts)
  end,
  diagnostics_buffer = function(opts)
    return peek_by_provider("diagnostics.in_buffer", opts)
  end,
  file_under_cursor = function(opts)
    return peek_by_provider("file.under_cursor", opts)
  end,
  grep = function(opts)
    return peek_by_provider("grep.search", opts)
  end,
  marks_buffer = function(opts)
    return peek_by_provider("marks.buffer", opts)
  end,
  marks_global = function(opts)
    return peek_by_provider("marks.global", opts)
  end,
  marks_all = function(opts)
    return peek_by_provider("marks.all", opts)
  end,
}, {
  __call = function(_, provider, opts)
    return peek_by_provider(provider, opts)
  end,
})

return M
