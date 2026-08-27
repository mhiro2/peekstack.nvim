local ui = require("peekstack.config.validate.rules.ui")
local picker = require("peekstack.config.validate.rules.picker")
local providers = require("peekstack.config.validate.rules.providers")
local persist = require("peekstack.config.validate.rules.persist")
local unknown = require("peekstack.config.validate.unknown")
local notify = require("peekstack.util.notify")

local M = {}

---Restore top-level sections (`ui`, `picker`, ...) that the user replaced with
---a non-table value. Field validators only descend into tables, so without
---this `setup({ ui = false })` would leave `cfg.ui == false` and crash the
---first consumer that indexes it.
---@param cfg table
---@param defaults PeekstackConfig
local function restore_sections(cfg, defaults)
  for key, default in pairs(defaults) do
    local value = cfg[key]
    if type(default) == "table" and value ~= nil and type(value) ~= "table" then
      notify.warn(string.format("%s must be a table, got %s. Falling back to defaults", key, type(value)))
      cfg[key] = vim.deepcopy(default)
    end
  end
end

---@param cfg table
---@param defaults PeekstackConfig
function M.run(cfg, defaults)
  -- Detect unknown keys first, before field validators can replace invalid
  -- subtrees with defaults (which would hide sibling typos).
  restore_sections(cfg, defaults)
  unknown.detect(cfg, defaults)
  ui.validate(cfg, defaults)
  picker.validate(cfg, defaults)
  providers.validate(cfg, defaults)
  persist.validate(cfg, defaults)
end

return M
