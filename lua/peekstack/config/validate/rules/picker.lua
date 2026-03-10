local shared = require("peekstack.config.validate.shared")

local M = {}

---@type string[]
local KNOWN_BACKENDS = { "builtin", "telescope", "fzf-lua", "snacks" }

---@type PeekstackConfigFieldRule[]
local PICKER_RULES = {
  { key = "backend", validate = shared.field_enum(KNOWN_BACKENDS), require_truthy = true },
}

---@param cfg table
---@param defaults PeekstackConfig
function M.validate(cfg, defaults)
  local picker = shared.as_table(cfg.picker)
  if picker then
    shared.apply_rules(picker, "picker", defaults.picker, PICKER_RULES)
  end
end

return M
