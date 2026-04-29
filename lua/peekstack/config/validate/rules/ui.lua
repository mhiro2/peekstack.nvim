local notify = require("peekstack.util.notify")
local shared = require("peekstack.config.validate.shared")

local M = {}

---@type string[]
local KNOWN_LAYOUT_STYLES = { "stack", "cascade", "single" }

---@type string[]
local KNOWN_BUFFER_MODES = { "copy", "source" }

---@type string[]
local KNOWN_RESTORE_POSITIONS = { "top", "original" }

---@type string[]
local KNOWN_PATH_BASES = { "repo", "cwd", "absolute" }

---@type string[]
local KNOWN_STACK_VIEW_POSITIONS = { "left", "right", "bottom" }

---@type PeekstackConfigFieldRule[]
local UI_PATH_RULES = {
  { key = "base", validate = shared.field_enum(KNOWN_PATH_BASES), require_truthy = true },
  { key = "max_width", validate = shared.validate_non_negative_number },
}

---@type PeekstackConfigFieldRule[]
local STACK_VIEW_RULES = {
  { key = "position", validate = shared.field_enum(KNOWN_STACK_VIEW_POSITIONS) },
}

---@type PeekstackConfigFieldRule[]
local POPUP_RULES = {
  { key = "editable", validate = shared.field_type("boolean") },
  { key = "buffer_mode", validate = shared.field_enum(KNOWN_BUFFER_MODES), require_truthy = true },
}

---@type PeekstackConfigFieldRule[]
local POPUP_SOURCE_RULES = {
  { key = "prevent_auto_close_if_modified", validate = shared.field_type("boolean") },
  { key = "confirm_on_close", validate = shared.field_type("boolean") },
}

---@type PeekstackConfigFieldRule[]
local POPUP_HISTORY_RULES = {
  { key = "max_items", validate = shared.field_number_range({ min = 1 }) },
  { key = "restore_position", validate = shared.field_enum(KNOWN_RESTORE_POSITIONS), require_truthy = true },
}

---@type PeekstackConfigFieldRule[]
local INLINE_PREVIEW_RULES = {
  { key = "enabled", validate = shared.field_type("boolean") },
  { key = "max_lines", validate = shared.field_number_range({ min = 1 }) },
  { key = "hl_group", validate = shared.field_type("string") },
  { key = "close_events", validate = shared.field_event_list() },
}

---@type PeekstackConfigFieldRule[]
local QUICK_PEEK_RULES = {
  { key = "close_events", validate = shared.field_event_list() },
}

---@type PeekstackConfigFieldRule[]
local POPUP_AUTO_CLOSE_RULES = {
  { key = "enabled", validate = shared.field_type("boolean") },
  { key = "idle_ms", validate = shared.field_number_range({ min = 1 }) },
  { key = "check_interval_ms", validate = shared.field_number_range({ min = 1 }) },
  { key = "ignore_pinned", validate = shared.field_type("boolean") },
}

---@type PeekstackConfigFieldRule[]
local FEEDBACK_RULES = {
  { key = "highlight_origin_on_close", validate = shared.field_type("boolean") },
}

---@type PeekstackConfigFieldRule[]
local PROMOTE_RULES = {
  { key = "close_popup", validate = shared.field_type("boolean") },
}

---@type PeekstackConfigFieldRule[]
local TITLE_RULES = {
  { key = "enabled", validate = shared.field_type("boolean") },
  { key = "format", validate = shared.field_type("string") },
}

---@type PeekstackConfigFieldRule[]
local TITLE_CONTEXT_RULES = {
  { key = "enabled", validate = shared.field_type("boolean") },
  { key = "max_depth", validate = shared.field_number_range({ min = 1 }) },
  { key = "separator", validate = shared.field_type("string") },
}

---@type PeekstackConfigFieldRule[]
local TITLE_ICON_RULES = {
  { key = "enabled", validate = shared.field_type("boolean") },
}

---@type PeekstackConfigFieldRule[]
local LAYOUT_RULES = {
  { key = "style", validate = shared.field_enum(KNOWN_LAYOUT_STYLES), require_truthy = true },
  { key = "max_ratio", validate = shared.field_ratio() },
  { key = "zindex_base", validate = shared.field_number_range({ min = 1 }) },
}

---@type PeekstackConfigFieldRule[]
local LAYOUT_MIN_SIZE_RULES = {
  { key = "w", validate = shared.field_number_range({ min = 1 }) },
  { key = "h", validate = shared.field_number_range({ min = 1 }) },
}

---@type PeekstackConfigFieldRule[]
local LAYOUT_SHRINK_RULES = {
  { key = "w", validate = shared.field_number_range({ min = 0 }) },
  { key = "h", validate = shared.field_number_range({ min = 0 }) },
}

---@type PeekstackConfigFieldRule[]
local LAYOUT_OFFSET_RULES = {
  { key = "row", validate = shared.field_number_range({ min = 0 }) },
  { key = "col", validate = shared.field_number_range({ min = 0 }) },
}

---@param map table
local function sanitize_icon_map(map)
  local invalid_keys = {}
  for key, value in pairs(map) do
    if type(key) ~= "string" or type(value) ~= "string" then
      invalid_keys[#invalid_keys + 1] = key
    end
  end
  for _, key in ipairs(invalid_keys) do
    notify.warn(
      string.format(
        "ui.title.icons.map[%s] must be a string mapping to a string. Dropping invalid entry",
        tostring(key)
      )
    )
    map[key] = nil
  end
end

---@param node_types table
local function sanitize_node_types(node_types)
  local invalid_keys = {}
  for filetype, list in pairs(node_types) do
    if type(filetype) ~= "string" then
      notify.warn(
        string.format("ui.title.context.node_types has non-string key %s. Dropping invalid entry", tostring(filetype))
      )
      invalid_keys[#invalid_keys + 1] = filetype
    elseif type(list) ~= "table" then
      notify.warn(
        string.format(
          "ui.title.context.node_types[%q] must be a list of strings, got %s. Dropping invalid entry",
          filetype,
          type(list)
        )
      )
      invalid_keys[#invalid_keys + 1] = filetype
    else
      local sanitized = {}
      local dropped = 0
      for _, node_type in ipairs(list) do
        if type(node_type) == "string" and node_type ~= "" then
          sanitized[#sanitized + 1] = node_type
        else
          dropped = dropped + 1
        end
      end
      if dropped > 0 then
        notify.warn(
          string.format(
            "ui.title.context.node_types[%q] contains %d invalid entries. Ignoring invalid values",
            filetype,
            dropped
          )
        )
      end
      if #sanitized == 0 then
        invalid_keys[#invalid_keys + 1] = filetype
      else
        node_types[filetype] = sanitized
      end
    end
  end
  for _, key in ipairs(invalid_keys) do
    node_types[key] = nil
  end
end

---@param ui table
---@param defaults PeekstackConfigUI
local function validate_keys(ui, defaults)
  if ui.keys == nil then
    return
  end

  local keys = shared.ensure_table_field(ui, "keys", "ui.keys", defaults.keys)
  if not keys then
    return
  end

  for name, val in pairs(keys) do
    if type(val) ~= "string" then
      notify.warn(
        string.format(
          "ui.keys.%s must be a string, got %s. Falling back to %s",
          name,
          type(val),
          tostring(defaults.keys[name])
        )
      )
      keys[name] = defaults.keys[name]
    end
  end
end

---@param ui table
---@param defaults PeekstackConfigUI
local function validate_popup(ui, defaults)
  if ui.popup == nil then
    return
  end
  local popup = shared.ensure_table_field(ui, "popup", "ui.popup", defaults.popup)
  if not popup then
    return
  end

  shared.apply_rules(popup, "ui.popup", defaults.popup, POPUP_RULES)

  if popup.source ~= nil then
    local source = shared.ensure_table_field(popup, "source", "ui.popup.source", defaults.popup.source)
    if source then
      shared.apply_rules(source, "ui.popup.source", defaults.popup.source, POPUP_SOURCE_RULES)
    end
  end

  if popup.history ~= nil then
    local history = shared.ensure_table_field(popup, "history", "ui.popup.history", defaults.popup.history)
    if history then
      shared.apply_rules(history, "ui.popup.history", defaults.popup.history, POPUP_HISTORY_RULES)
    end
  end

  if popup.auto_close ~= nil then
    local auto_close = shared.ensure_table_field(popup, "auto_close", "ui.popup.auto_close", defaults.popup.auto_close)
    if auto_close then
      shared.apply_rules(auto_close, "ui.popup.auto_close", defaults.popup.auto_close, POPUP_AUTO_CLOSE_RULES)
    end
  end
end

---@param ui table
---@param defaults PeekstackConfigUI
local function validate_path(ui, defaults)
  if ui.path == nil then
    return
  end
  local path = shared.ensure_table_field(ui, "path", "ui.path", defaults.path)
  if path then
    shared.apply_rules(path, "ui.path", defaults.path, UI_PATH_RULES)
  end
end

---@param ui table
---@param defaults PeekstackConfigUI
local function validate_stack_view(ui, defaults)
  if ui.stack_view == nil then
    return
  end

  local stack_view = shared.ensure_table_field(ui, "stack_view", "ui.stack_view", defaults.stack_view)
  if stack_view then
    shared.apply_rules(stack_view, "ui.stack_view", defaults.stack_view, STACK_VIEW_RULES)
  end
end

---@param ui table
---@param defaults PeekstackConfigUI
local function validate_preview(ui, defaults)
  if ui.inline_preview ~= nil then
    local inline_preview = shared.ensure_table_field(ui, "inline_preview", "ui.inline_preview", defaults.inline_preview)
    if inline_preview then
      shared.apply_rules(inline_preview, "ui.inline_preview", defaults.inline_preview, INLINE_PREVIEW_RULES)
    end
  end

  if ui.quick_peek ~= nil then
    local quick_peek = shared.ensure_table_field(ui, "quick_peek", "ui.quick_peek", defaults.quick_peek)
    if quick_peek then
      shared.apply_rules(quick_peek, "ui.quick_peek", defaults.quick_peek, QUICK_PEEK_RULES)
    end
  end
end

---@param ui table
---@param defaults PeekstackConfigTitle
local function validate_title(ui, defaults)
  if ui.title == nil then
    return
  end
  local title = shared.ensure_table_field(ui, "title", "ui.title", defaults)
  if not title then
    return
  end

  shared.apply_rules(title, "ui.title", defaults, TITLE_RULES)

  if title.icons ~= nil and type(title.icons) ~= "table" then
    notify.warn("ui.title.icons must be a table, got " .. type(title.icons) .. ". Falling back to defaults")
    title.icons = vim.deepcopy(defaults.icons)
    return
  end

  if type(title.icons) == "table" then
    local icons = title.icons
    shared.apply_rules(icons, "ui.title.icons", defaults.icons, TITLE_ICON_RULES)
    if icons.map ~= nil and type(icons.map) ~= "table" then
      notify.warn("ui.title.icons.map must be a table, got " .. type(icons.map) .. ". Falling back to defaults")
      icons.map = vim.deepcopy(defaults.icons.map)
    elseif type(icons.map) == "table" then
      sanitize_icon_map(icons.map)
    end
  end

  if title.context ~= nil then
    local context = shared.ensure_table_field(title, "context", "ui.title.context", defaults.context)
    if context then
      shared.apply_rules(context, "ui.title.context", defaults.context, TITLE_CONTEXT_RULES)
      if context.node_types ~= nil then
        if type(context.node_types) ~= "table" then
          notify.warn(
            "ui.title.context.node_types must be a table, got "
              .. type(context.node_types)
              .. ". Falling back to defaults"
          )
          context.node_types = vim.deepcopy(defaults.context.node_types)
        else
          sanitize_node_types(context.node_types)
        end
      end
    end
  end
end

---@param ui table
---@param defaults PeekstackConfigUI
local function validate_layout(ui, defaults)
  if ui.layout == nil then
    return
  end

  local layout = shared.ensure_table_field(ui, "layout", "ui.layout", defaults.layout)
  if not layout then
    return
  end

  shared.apply_rules(layout, "ui.layout", defaults.layout, LAYOUT_RULES)

  if layout.min_size ~= nil then
    local min_size = shared.ensure_table_field(layout, "min_size", "ui.layout.min_size", defaults.layout.min_size)
    if min_size then
      shared.apply_rules(min_size, "ui.layout.min_size", defaults.layout.min_size, LAYOUT_MIN_SIZE_RULES)
    end
  end

  if layout.shrink ~= nil then
    local shrink = shared.ensure_table_field(layout, "shrink", "ui.layout.shrink", defaults.layout.shrink)
    if shrink then
      shared.apply_rules(shrink, "ui.layout.shrink", defaults.layout.shrink, LAYOUT_SHRINK_RULES)
    end
  end

  if layout.offset ~= nil then
    local offset = shared.ensure_table_field(layout, "offset", "ui.layout.offset", defaults.layout.offset)
    if offset then
      shared.apply_rules(offset, "ui.layout.offset", defaults.layout.offset, LAYOUT_OFFSET_RULES)
    end
  end
end

---@param cfg table
---@param defaults PeekstackConfig
function M.validate(cfg, defaults)
  local ui = shared.as_table(cfg.ui)
  if not ui then
    return
  end

  validate_keys(ui, defaults.ui)
  validate_popup(ui, defaults.ui)
  validate_path(ui, defaults.ui)
  validate_stack_view(ui, defaults.ui)
  validate_preview(ui, defaults.ui)
  validate_title(ui, defaults.ui.title)
  validate_layout(ui, defaults.ui)

  if ui.feedback ~= nil then
    local feedback = shared.ensure_table_field(ui, "feedback", "ui.feedback", defaults.ui.feedback)
    if feedback then
      shared.apply_rules(feedback, "ui.feedback", defaults.ui.feedback, FEEDBACK_RULES)
    end
  end

  if ui.promote ~= nil then
    local promote = shared.ensure_table_field(ui, "promote", "ui.promote", defaults.ui.promote)
    if promote then
      shared.apply_rules(promote, "ui.promote", defaults.ui.promote, PROMOTE_RULES)
    end
  end
end

return M
