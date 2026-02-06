local M = {}

---@type table<string, fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))>
local providers = {}

---@class PeekstackPicker
---@field pick fun(locations: PeekstackLocation[], opts?: table, cb: fun(location: PeekstackLocation))

---@type table<string, PeekstackPicker>
local pickers = {}

local function set_hl()
  vim.api.nvim_set_hl(0, "PeekstackOrigin", { default = true, link = "IncSearch" })
  vim.api.nvim_set_hl(0, "PeekstackStackViewIndex", { default = true, link = "LineNr" })
  vim.api.nvim_set_hl(0, "PeekstackStackViewPinned", { default = true, link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "PeekstackStackViewProvider", { default = true, link = "Type" })
  vim.api.nvim_set_hl(0, "PeekstackStackViewPath", { default = true, link = "Directory" })
  vim.api.nvim_set_hl(0, "PeekstackStackViewFilter", { default = true, link = "Search" })
  vim.api.nvim_set_hl(0, "PeekstackStackViewHeader", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "PeekstackStackViewEmpty", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "PeekstackStackViewCursorLine", { default = true, link = "CursorLine" })
  vim.api.nvim_set_hl(0, "PeekstackInlinePreview", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "PeekstackTitleProvider", { default = true, link = "Type" })
  vim.api.nvim_set_hl(0, "PeekstackTitlePath", { default = true, link = "Directory" })
  vim.api.nvim_set_hl(0, "PeekstackTitleKindError", { default = true, link = "DiagnosticError" })
  vim.api.nvim_set_hl(0, "PeekstackTitleKindWarn", { default = true, link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "PeekstackTitleKindInfo", { default = true, link = "DiagnosticInfo" })
  vim.api.nvim_set_hl(0, "PeekstackTitleKindHint", { default = true, link = "DiagnosticHint" })
end

---@param name string
---@param fn fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))
function M.register_provider(name, fn)
  providers[name] = fn
end

---@param name string
---@param fn PeekstackPicker
function M.register_picker(name, fn)
  pickers[name] = fn
end

---@param prefix string
---@param provider_mod table
---@param names string[]
local function register_providers(prefix, provider_mod, names)
  for _, name in ipairs(names) do
    local fn = provider_mod[name]
    if fn then
      M.register_provider(prefix .. name, fn)
    end
  end
end

---@param name string
---@return fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))?
local function ensure_provider(name)
  return providers[name]
end

---@return PeekstackPicker
local function pick_backend()
  local config = require("peekstack.config")
  local backend = config.get().picker.backend
  return pickers[backend] or pickers.builtin
end

---@param name string?
---@return boolean
local function is_lsp_provider(name)
  return type(name) == "string" and name:match("^lsp%.") ~= nil
end

---Normalize location and set provider from opts if needed
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

  vim.notify("Invalid location payload: expected uri/range", vim.log.levels.WARN)
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
      local inline_preview = require("peekstack.ui.inline_preview")
      inline_preview.open(normalized, opts)
      return
    end
    -- Fallback to stack mode when inline preview is disabled
    mode = nil
  end

  if mode == "quick" then
    local stack = require("peekstack.core.stack")
    stack.push(normalized, vim.tbl_extend("force", opts, { stack = false }))
  else
    local stack = require("peekstack.core.stack")
    stack.push(normalized, opts)
  end
end

---@param locations? PeekstackLocation[]
---@param opts? table
function M.peek_locations(locations, opts)
  if not locations or #locations == 0 then
    vim.notify("No locations", vim.log.levels.INFO)
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

--- Peek a location by provider name. This is the core dispatch function.
---@param provider string
---@param opts? table
local function peek_by_provider(provider, opts)
  local fn = ensure_provider(provider)
  if not fn then
    vim.notify("Unknown provider: " .. tostring(provider), vim.log.levels.WARN)
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
        filtered = {}
        for _, loc in ipairs(locations) do
          local normalized = location_mod.normalize(loc, provider)
          if normalized and not location_mod.is_same_position(normalized, uri, pos.line, pos.character) then
            table.insert(filtered, normalized)
          end
        end
      end
    end
    M.peek_locations(filtered, merged)
  end)
end

--- `M.peek` is a callable table: call `M.peek("provider", opts)` directly,
--- or use convenience shortcuts like `M.peek.definition(opts)`.
---@type table
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

---@param opts? table
function M.setup(opts)
  local config = require("peekstack.config")
  local events = require("peekstack.core.events")
  local commands = require("peekstack.commands")
  local persist_auto = require("peekstack.persist.auto")

  providers = {}
  pickers = {}

  config.setup(opts)
  set_hl()
  events.setup()
  commands.setup()

  local cfg = config.get()

  M.register_picker("builtin", require("peekstack.picker.builtin"))
  local backend = cfg.picker.backend
  if backend ~= "builtin" then
    local picker_map = {
      telescope = "peekstack.picker.telescope",
      ["fzf-lua"] = "peekstack.picker.fzf_lua",
      snacks = "peekstack.picker.snacks",
    }
    local mod_name = picker_map[backend]
    if mod_name then
      local ok, picker_mod = pcall(require, mod_name)
      if ok then
        M.register_picker(backend, picker_mod)
      end
    end
  end

  if cfg.providers.lsp.enable then
    local lsp_provider = require("peekstack.providers.lsp")
    register_providers("lsp.", lsp_provider, {
      "definition",
      "implementation",
      "references",
      "type_definition",
      "declaration",
    })
  end

  if cfg.providers.diagnostics.enable then
    local diag_provider = require("peekstack.providers.diagnostics")
    register_providers("diagnostics.", diag_provider, {
      "under_cursor",
      "in_buffer",
    })
  end

  if cfg.providers.file.enable then
    local file_provider = require("peekstack.providers.file")
    register_providers("file.", file_provider, { "under_cursor" })
  end

  local grep_provider = require("peekstack.providers.grep")
  register_providers("grep.", grep_provider, { "search" })

  if cfg.providers.marks.enable then
    local marks_provider = require("peekstack.providers.marks")
    register_providers("marks.", marks_provider, { "buffer", "global", "all" })
  end

  persist_auto.setup()
end

---@return table
M.stack = setmetatable({}, {
  __index = function(_, k)
    return require("peekstack.core.stack")[k]
  end,
})

---@return table
M.persist = setmetatable({}, {
  __index = function(_, k)
    return require("peekstack.persist")[k]
  end,
})

return M
