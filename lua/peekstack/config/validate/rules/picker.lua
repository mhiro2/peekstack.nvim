local notify = require("peekstack.util.notify")
local shared = require("peekstack.config.validate.shared")

local M = {}

---Any non-empty string is accepted so pickers registered through
---`register_picker()` can be selected. Availability of the backend is
---checked at pick time (falling back to `builtin`) and by `:checkhealth`.
---@param path string
---@param value any
---@param default string
---@return string
local function validate_backend(path, value, default)
  if type(value) ~= "string" or value == "" then
    notify.warn(
      string.format("%s must be a non-empty string, got %s. Falling back to %q", path, vim.inspect(value), default)
    )
    return default
  end
  return value
end

---@type PeekstackConfigFieldRule[]
local PICKER_RULES = {
  { key = "backend", validate = validate_backend, require_truthy = true },
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
