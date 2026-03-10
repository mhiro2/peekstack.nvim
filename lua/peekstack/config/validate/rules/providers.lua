local shared = require("peekstack.config.validate.shared")

local M = {}

---@type PeekstackConfigFieldRule[]
local PROVIDER_ENABLE_RULES = {
  { key = "enable", validate = shared.field_type("boolean") },
}

---@type PeekstackConfigFieldRule[]
local MARKS_RULES = {
  { key = "enable", validate = shared.field_type("boolean") },
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

  for _, name in ipairs({ "lsp", "diagnostics", "file" }) do
    if providers[name] ~= nil then
      local provider = shared.ensure_table_field(providers, name, "providers." .. name, defaults.providers[name])
      if provider then
        shared.apply_rules(provider, "providers." .. name, defaults.providers[name], PROVIDER_ENABLE_RULES)
      end
    end
  end

  if providers.marks ~= nil then
    local marks = shared.ensure_table_field(providers, "marks", "providers.marks", defaults.providers.marks)
    if marks then
      shared.apply_rules(marks, "providers.marks", defaults.providers.marks, MARKS_RULES)
    end
  end
end

return M
