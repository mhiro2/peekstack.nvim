local notify = require("peekstack.util.notify")

local M = {}

---@alias PeekstackConfigFieldValidator fun(path: string, value: any, default: any): any

---@class PeekstackConfigFieldRule
---@field key string
---@field validate PeekstackConfigFieldValidator
---@field assign? boolean
---@field require_truthy? boolean

---@param value any
---@return string
local function format_value(value)
  if type(value) == "string" then
    return string.format("%q", value)
  end
  return tostring(value)
end

---@param path string
---@param expected_type string
---@param value any
---@param default any
---@return any
function M.validate_type(path, expected_type, value, default)
  if type(value) ~= expected_type then
    notify.warn(
      string.format("%s must be a %s, got %s. Falling back to %s", path, expected_type, type(value), tostring(default))
    )
    return default
  end
  return value
end

---@param path string
---@param value any
---@param default number
---@param opts? { min: number?, max: number? }
---@return number
function M.validate_number_range(path, value, default, opts)
  if type(value) ~= "number" then
    notify.warn(string.format("%s must be a number, got %s. Falling back to %s", path, type(value), default))
    return default
  end
  if opts and opts.min ~= nil and value < opts.min then
    notify.warn(string.format("%s must be >= %s, got %s. Falling back to %s", path, opts.min, value, default))
    return default
  end
  if opts and opts.max ~= nil and value > opts.max then
    notify.warn(string.format("%s must be <= %s, got %s. Falling back to %s", path, opts.max, value, default))
    return default
  end
  return value
end

---@param path string
---@param value any
---@param default number
---@return number
function M.validate_ratio(path, value, default)
  if type(value) ~= "number" then
    notify.warn(string.format("%s must be a number, got %s. Falling back to %s", path, type(value), default))
    return default
  end
  if value <= 0 or value > 1 then
    notify.warn(string.format("%s must be in (0, 1], got %s. Falling back to %s", path, value, default))
    return default
  end
  return value
end

---@param path string
---@param value any
---@param default string[]
---@return string[]
function M.sanitize_event_list(path, value, default)
  if type(value) ~= "table" then
    notify.warn(string.format("%s must be a list of strings. Falling back to defaults", path))
    return vim.deepcopy(default)
  end

  ---@type string[]
  local events = {}
  local invalid_count = 0
  for _, event in ipairs(value) do
    if type(event) == "string" and event ~= "" then
      events[#events + 1] = event
    else
      invalid_count = invalid_count + 1
    end
  end

  if invalid_count > 0 then
    notify.warn(string.format("%s contains %d invalid entries. Ignoring invalid values", path, invalid_count))
  end

  if #events == 0 then
    notify.warn(string.format("%s must contain at least one valid event. Falling back to defaults", path))
    return vim.deepcopy(default)
  end

  return events
end

---@param path string
---@param value any
---@param known string[]
---@param default string
---@return string
function M.validate_enum(path, value, known, default)
  if not vim.list_contains(known, value) then
    notify.warn(
      string.format(
        "Unknown %s: %s (known: %s). Falling back to %q",
        path,
        format_value(value),
        table.concat(known, ", "),
        default
      )
    )
    return default
  end
  return value
end

---@param path string
---@param value any
---@param default number
---@return number
function M.validate_non_negative_number(path, value, default)
  if type(value) ~= "number" then
    notify.warn(string.format("%s must be a number, got %s", path, type(value)))
    return default
  end
  if value < 0 then
    notify.warn(string.format("%s must be >= 0, got %s", path, value))
    return default
  end
  return value
end

---@param expected_type string
---@return PeekstackConfigFieldValidator
function M.field_type(expected_type)
  return function(path, value, default)
    return M.validate_type(path, expected_type, value, default)
  end
end

---@param known string[]
---@return PeekstackConfigFieldValidator
function M.field_enum(known)
  return function(path, value, default)
    return M.validate_enum(path, value, known, default)
  end
end

---@param opts { min: number?, max: number? }
---@return PeekstackConfigFieldValidator
function M.field_number_range(opts)
  return function(path, value, default)
    return M.validate_number_range(path, value, default, opts)
  end
end

---@return PeekstackConfigFieldValidator
function M.field_ratio()
  return function(path, value, default)
    return M.validate_ratio(path, value, default)
  end
end

---@return PeekstackConfigFieldValidator
function M.field_event_list()
  return function(path, value, default)
    return M.sanitize_event_list(path, value, default)
  end
end

---@param value any
---@return table?
function M.as_table(value)
  if type(value) == "table" then
    return value
  end
  return nil
end

---@param parent table
---@param key string
---@param path string
---@param defaults table
---@param opts? { fallback: boolean?, message: string? }
---@return table?
function M.ensure_table_field(parent, key, path, defaults, opts)
  local value = parent[key]
  if value == nil then
    return nil
  end
  if type(value) == "table" then
    return value
  end

  if opts and opts.message then
    notify.warn(opts.message)
  else
    notify.warn(string.format("%s must be a table, got %s. Falling back to defaults", path, type(value)))
  end

  if opts and opts.fallback == false then
    return nil
  end

  parent[key] = vim.deepcopy(defaults)
  return parent[key]
end

---@param section table
---@param path string
---@param defaults table
---@param rules PeekstackConfigFieldRule[]
function M.apply_rules(section, path, defaults, rules)
  for _, rule in ipairs(rules) do
    local value = section[rule.key]
    local should_apply = value ~= nil
    if rule.require_truthy then
      should_apply = not not value
    end
    if should_apply then
      local validated = rule.validate(path .. "." .. rule.key, value, defaults[rule.key])
      if rule.assign ~= false then
        section[rule.key] = validated
      end
    end
  end
end

return M
