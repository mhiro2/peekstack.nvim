local commands = require("peekstack.commands")
local config = require("peekstack.config")
local events = require("peekstack.core.events")
local highlights = require("peekstack.highlights")
local persist_auto = require("peekstack.persist.auto")
local registry = require("peekstack.registry")
local stack_view = require("peekstack.ui.stack_view")

local M = {}

---@type table<string, string>
local PICKER_MODULES = {
  telescope = "peekstack.picker.telescope",
  ["fzf-lua"] = "peekstack.picker.fzf_lua",
  snacks = "peekstack.picker.snacks",
}

---@type { enabled: fun(cfg: PeekstackConfig): boolean, prefix: string, module: string, names: string[] }[]
local PROVIDER_GROUPS = {
  {
    enabled = function(cfg)
      return cfg.providers.lsp.enable
    end,
    prefix = "lsp.",
    module = "peekstack.providers.lsp",
    names = {
      "definition",
      "implementation",
      "references",
      "type_definition",
      "declaration",
      "symbols_document",
    },
  },
  {
    enabled = function(cfg)
      return cfg.providers.diagnostics.enable
    end,
    prefix = "diagnostics.",
    module = "peekstack.providers.diagnostics",
    names = { "under_cursor", "in_buffer" },
  },
  {
    enabled = function(cfg)
      return cfg.providers.file.enable
    end,
    prefix = "file.",
    module = "peekstack.providers.file",
    names = { "under_cursor" },
  },
  {
    enabled = function(_cfg)
      return true
    end,
    prefix = "grep.",
    module = "peekstack.providers.grep",
    names = { "search" },
  },
  {
    enabled = function(cfg)
      return cfg.providers.marks.enable
    end,
    prefix = "marks.",
    module = "peekstack.providers.marks",
    names = { "buffer", "global", "all" },
  },
}

---@param cfg PeekstackConfig
local function register_picker_backends(cfg)
  registry.register_picker("builtin", require("peekstack.picker.builtin"))

  local backend = cfg.picker.backend
  if backend == "builtin" then
    return
  end

  local mod_name = PICKER_MODULES[backend]
  if not mod_name then
    return
  end

  local ok, picker_mod = pcall(require, mod_name)
  if ok then
    registry.register_picker(backend, picker_mod)
  end
end

---@param cfg PeekstackConfig
local function register_provider_backends(cfg)
  for _, entry in ipairs(PROVIDER_GROUPS) do
    if entry.enabled(cfg) then
      registry.register_provider_group(entry.prefix, require(entry.module), entry.names)
    end
  end
end

---@param opts? table
function M.run(opts)
  registry.reset()

  config.setup(opts)
  highlights.apply()
  events.setup()
  commands.setup()
  stack_view.setup()

  local cfg = config.get()
  register_picker_backends(cfg)
  register_provider_backends(cfg)
  persist_auto.setup()
end

return M
