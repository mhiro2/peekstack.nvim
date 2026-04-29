local shared = require("peekstack.config.validate.shared")

local M = {}

---@type PeekstackConfigFieldRule[]
local PERSIST_RULES = {
  { key = "enabled", validate = shared.field_type("boolean") },
  { key = "max_items", validate = shared.field_number_range({ min = 1 }) },
}

---@type PeekstackConfigFieldRule[]
local PERSIST_SESSION_RULES = {
  { key = "default_name", validate = shared.field_type("string") },
  { key = "prompt_if_missing", validate = shared.field_type("boolean") },
}

---@type PeekstackConfigFieldRule[]
local PERSIST_AUTO_RULES = {
  { key = "enabled", validate = shared.field_type("boolean") },
  { key = "session_name", validate = shared.field_type("string") },
  { key = "restore", validate = shared.field_type("boolean") },
  { key = "save", validate = shared.field_type("boolean") },
  { key = "restore_if_empty", validate = shared.field_type("boolean") },
  { key = "debounce_ms", validate = shared.field_number_range({ min = 0, max = 600000 }) },
  { key = "save_on_leave", validate = shared.field_type("boolean") },
}

---@param cfg table
---@param defaults PeekstackConfig
function M.validate(cfg, defaults)
  local persist = shared.as_table(cfg.persist)
  if not persist then
    return
  end

  shared.apply_rules(persist, "persist", defaults.persist, PERSIST_RULES)

  if persist.session ~= nil then
    local session = shared.ensure_table_field(persist, "session", "persist.session", defaults.persist.session)
    if session then
      shared.apply_rules(session, "persist.session", defaults.persist.session, PERSIST_SESSION_RULES)
    end
  end

  if persist.auto ~= nil then
    local auto = shared.ensure_table_field(
      persist,
      "auto",
      "persist.auto",
      defaults.persist.auto,
      { fallback = false, message = "persist.auto must be a table" }
    )
    if auto then
      shared.apply_rules(auto, "persist.auto", defaults.persist.auto, PERSIST_AUTO_RULES)
    end
  end
end

return M
