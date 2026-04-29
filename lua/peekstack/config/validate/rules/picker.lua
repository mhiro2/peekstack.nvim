local shared = require("peekstack.config.validate.shared")

local M = {}

---@type string[]
local KNOWN_BACKENDS = { "builtin", "telescope", "fzf-lua", "snacks" }

---@type PeekstackConfigFieldRule[]
local PICKER_RULES = {
  { key = "backend", validate = shared.field_enum(KNOWN_BACKENDS), require_truthy = true },
}

---@type PeekstackConfigFieldRule[]
local PICKER_BUILTIN_RULES = {
  { key = "preview_lines", validate = shared.field_number_range({ min = 0 }) },
}

---@param cfg table
---@param defaults PeekstackConfig
function M.validate(cfg, defaults)
  local picker = shared.as_table(cfg.picker)
  if not picker then
    return
  end

  shared.apply_rules(picker, "picker", defaults.picker, PICKER_RULES)

  if picker.builtin ~= nil then
    local builtin = shared.ensure_table_field(picker, "builtin", "picker.builtin", defaults.picker.builtin)
    if builtin then
      shared.apply_rules(builtin, "picker.builtin", defaults.picker.builtin, PICKER_BUILTIN_RULES)
    end
  end
end

return M
