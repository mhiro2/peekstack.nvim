local shared = require("peekstack.config.validate.shared")

local M = {}

---@type PeekstackConfigFieldRule[]
local MARKS_RULES = {
  { key = "include", validate = shared.field_type("string") },
  { key = "include_special", validate = shared.field_type("boolean") },
}

---@param cfg table
---@param defaults PeekstackConfig
function M.validate(cfg, defaults)
  local providers = shared.as_table(cfg.providers)
  if not providers then
    return
  end

  local marks = shared.as_table(providers.marks)
  if marks then
    shared.apply_rules(marks, "providers.marks", defaults.providers.marks, MARKS_RULES)
  end
end

return M
