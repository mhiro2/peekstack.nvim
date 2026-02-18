local notify = require("peekstack.util.notify")

local M = {}

local DEFAULT_CLOSE_EVENTS = { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" }

---@type string[]
local KNOWN_BACKENDS = { "builtin", "telescope", "fzf-lua", "snacks" }

---@type string[]
local KNOWN_LAYOUT_STYLES = { "stack", "cascade", "single" }

---@type string[]
local KNOWN_BUFFER_MODES = { "copy", "source" }

---@type string[]
local KNOWN_RESTORE_POSITIONS = { "top", "original" }

---@type string[]
local KNOWN_MARK_SCOPES = { "buffer", "global", "all" }

---@type string[]
local KNOWN_PATH_BASES = { "repo", "cwd", "absolute" }

---@type string[]
local KNOWN_STACK_VIEW_POSITIONS = { "left", "right", "bottom" }

---@param path string
---@param expected_type string
---@param value any
---@param default any
---@return any
local function validate_type(path, expected_type, value, default)
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
local function validate_number_range(path, value, default, opts)
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
local function validate_ratio(path, value, default)
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

---@type PeekstackConfig
M.defaults = {
  ui = {
    layout = {
      style = "stack",
      offset = { row = 1, col = 4 },
      shrink = { w = 4, h = 2 },
      min_size = { w = 60, h = 12 },
      max_ratio = 0.65,
      zindex_base = 50,
    },
    title = {
      enabled = true,
      format = "{icon}{kind}{provider} {path}:{line}{context}",
      icons = {
        enabled = true,
        map = {
          lsp = " ",
          diagnostics = " ",
          grep = " ",
          file = " ",
          marks = " ",
        },
      },
      context = {
        enabled = false,
        max_depth = 5,
        separator = " • ",
        node_types = {},
      },
    },
    path = {
      base = "repo",
      max_width = 80,
    },
    stack_view = {
      position = "right",
    },
    inline_preview = {
      enabled = true,
      max_lines = 10,
      hl_group = "PeekstackInlinePreview",
      close_events = DEFAULT_CLOSE_EVENTS,
    },
    quick_peek = {
      close_events = DEFAULT_CLOSE_EVENTS,
    },
    popup = {
      editable = false,
      buffer_mode = "copy",
      source = {
        prevent_auto_close_if_modified = true,
        confirm_on_close = true,
      },
      history = {
        max_items = 50,
        restore_position = "top",
      },
      auto_close = {
        enabled = false,
        idle_ms = 300000,
        check_interval_ms = 60000,
        ignore_pinned = true,
      },
    },
    feedback = {
      highlight_origin_on_close = true,
    },
    promote = {
      close_popup = true,
    },
    keys = {
      close = "q",
      focus_next = "<C-j>",
      focus_prev = "<C-k>",
      promote_split = "<C-x>",
      promote_vsplit = "<C-v>",
      promote_tab = "<C-t>",
      toggle_stack_view = "<leader>os",
    },
  },
  picker = {
    backend = "builtin",
    builtin = {
      preview_lines = 1,
    },
  },
  providers = {
    lsp = { enable = true },
    diagnostics = { enable = true },
    file = { enable = true },
    marks = {
      enable = false,
      scope = "all",
      include = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
      include_special = false,
    },
  },
  persist = {
    enabled = false,
    max_items = 200,
    session = {
      default_name = "default",
      prompt_if_missing = true,
    },
    auto = {
      enabled = false,
      session_name = "auto",
      restore = true,
      save = true,
      restore_if_empty = true,
      debounce_ms = 1000,
      save_on_leave = true,
    },
  },
}

---@type PeekstackConfig
local config = vim.deepcopy(M.defaults)

---@param path string
---@param value any
local function validate_event_list(path, value)
  if type(value) ~= "table" then
    notify.warn(string.format("%s must be a list of strings", path))
    return
  end
  for idx, event in ipairs(value) do
    if type(event) ~= "string" then
      notify.warn(string.format("%s[%d] must be a string, got %s", path, idx, type(event)))
      return
    end
  end
end

---@alias PeekstackConfigFieldValidator fun(path: string, value: any, default: any): any

---@class PeekstackConfigFieldRule
---@field key string
---@field validate PeekstackConfigFieldValidator
---@field assign? boolean
---@field require_truthy? boolean

---@param path string
---@param value any
---@param known string[]
---@param default string
---@return string
local function validate_enum(path, value, known, default)
  if not vim.list_contains(known, value) then
    notify.warn(
      string.format("Unknown %s: %q (known: %s). Falling back to %q", path, value, table.concat(known, ", "), default)
    )
    return default
  end
  return value
end

---@param expected_type string
---@return PeekstackConfigFieldValidator
local function field_type(expected_type)
  return function(path, value, default)
    return validate_type(path, expected_type, value, default)
  end
end

---@param known string[]
---@return PeekstackConfigFieldValidator
local function field_enum(known)
  return function(path, value, default)
    return validate_enum(path, value, known, default)
  end
end

---@param opts { min: number?, max: number? }
---@return PeekstackConfigFieldValidator
local function field_number_range(opts)
  return function(path, value, default)
    return validate_number_range(path, value, default, opts)
  end
end

---@return PeekstackConfigFieldValidator
local function field_ratio()
  return function(path, value, default)
    return validate_ratio(path, value, default)
  end
end

---@return PeekstackConfigFieldValidator
local function field_event_list()
  return function(path, value, _default)
    validate_event_list(path, value)
    return value
  end
end

---@param path string
---@param value any
---@param default number
---@return number
local function validate_non_negative_number(path, value, default)
  if type(value) ~= "number" then
    notify.warn(string.format("%s must be a number, got %s", path, type(value)))
    return value
  end
  if value < 0 then
    notify.warn(string.format("%s must be >= 0, got %s", path, value))
    return default
  end
  return value
end

---@param value any
---@return table?
local function as_table(value)
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
local function ensure_table_field(parent, key, path, defaults, opts)
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
local function apply_rules(section, path, defaults, rules)
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

---@type PeekstackConfigFieldRule[]
local UI_PATH_RULES = {
  { key = "base", validate = field_enum(KNOWN_PATH_BASES), require_truthy = true },
  { key = "max_width", validate = validate_non_negative_number },
}

---@type PeekstackConfigFieldRule[]
local STACK_VIEW_RULES = {
  { key = "position", validate = field_enum(KNOWN_STACK_VIEW_POSITIONS) },
}

---@type PeekstackConfigFieldRule[]
local POPUP_RULES = {
  { key = "editable", validate = field_type("boolean") },
  { key = "buffer_mode", validate = field_enum(KNOWN_BUFFER_MODES), require_truthy = true },
}

---@type PeekstackConfigFieldRule[]
local POPUP_SOURCE_RULES = {
  { key = "prevent_auto_close_if_modified", validate = field_type("boolean") },
  { key = "confirm_on_close", validate = field_type("boolean") },
}

---@type PeekstackConfigFieldRule[]
local POPUP_HISTORY_RULES = {
  { key = "max_items", validate = field_number_range({ min = 1 }) },
  { key = "restore_position", validate = field_enum(KNOWN_RESTORE_POSITIONS), require_truthy = true },
}

---@type PeekstackConfigFieldRule[]
local INLINE_PREVIEW_RULES = {
  { key = "enabled", validate = field_type("boolean") },
  { key = "max_lines", validate = field_number_range({ min = 1 }) },
  { key = "hl_group", validate = field_type("string") },
  { key = "close_events", validate = field_event_list() },
}

---@type PeekstackConfigFieldRule[]
local QUICK_PEEK_RULES = {
  { key = "close_events", validate = field_event_list() },
}

---@type PeekstackConfigFieldRule[]
local TITLE_ICON_RULES = {
  { key = "enabled", validate = field_type("boolean") },
}

---@type PeekstackConfigFieldRule[]
local PICKER_RULES = {
  { key = "backend", validate = field_enum(KNOWN_BACKENDS), require_truthy = true },
}

---@type PeekstackConfigFieldRule[]
local LAYOUT_RULES = {
  { key = "style", validate = field_enum(KNOWN_LAYOUT_STYLES), require_truthy = true },
  { key = "max_ratio", validate = field_ratio() },
}

---@type PeekstackConfigFieldRule[]
local LAYOUT_MIN_SIZE_RULES = {
  { key = "w", validate = field_number_range({ min = 1 }) },
  { key = "h", validate = field_number_range({ min = 1 }) },
}

---@type PeekstackConfigFieldRule[]
local LAYOUT_SHRINK_RULES = {
  { key = "w", validate = field_number_range({ min = 0 }) },
  { key = "h", validate = field_number_range({ min = 0 }) },
}

---@type PeekstackConfigFieldRule[]
local LAYOUT_OFFSET_RULES = {
  { key = "row", validate = field_number_range({ min = 0 }) },
  { key = "col", validate = field_number_range({ min = 0 }) },
}

---@type PeekstackConfigFieldRule[]
local MARKS_RULES = {
  { key = "scope", validate = field_enum(KNOWN_MARK_SCOPES), require_truthy = true },
  { key = "include", validate = field_type("string") },
  { key = "include_special", validate = field_type("boolean") },
}

---@type PeekstackConfigFieldRule[]
local PERSIST_RULES = {
  { key = "max_items", validate = field_number_range({ min = 1 }) },
}

---@type PeekstackConfigFieldRule[]
local PERSIST_SESSION_RULES = {
  { key = "default_name", validate = field_type("string") },
  { key = "prompt_if_missing", validate = field_type("boolean") },
}

---@type PeekstackConfigFieldRule[]
local PERSIST_AUTO_RULES = {
  { key = "enabled", validate = field_type("boolean") },
  { key = "session_name", validate = field_type("string") },
  { key = "restore", validate = field_type("boolean") },
  { key = "save", validate = field_type("boolean") },
  { key = "restore_if_empty", validate = field_type("boolean") },
  { key = "debounce_ms", validate = field_type("number") },
  { key = "save_on_leave", validate = field_type("boolean") },
}

---@param cfg table
local function validate_ui_keys(cfg)
  local ui = as_table(cfg.ui)
  if not ui or ui.keys == nil then
    return
  end

  local keys = ensure_table_field(ui, "keys", "ui.keys", M.defaults.ui.keys)
  if not keys then
    return
  end

  local defaults = M.defaults.ui.keys
  for name, val in pairs(keys) do
    if type(val) ~= "string" then
      notify.warn(
        string.format(
          "ui.keys.%s must be a string, got %s. Falling back to %s",
          name,
          type(val),
          tostring(defaults[name])
        )
      )
      keys[name] = defaults[name]
    end
  end
end

---@param cfg table
local function validate(cfg)
  validate_ui_keys(cfg)

  local ui = as_table(cfg.ui)
  if ui then
    local popup = as_table(ui.popup)
    if popup then
      apply_rules(popup, "ui.popup", M.defaults.ui.popup, POPUP_RULES)

      local source = as_table(popup.source)
      if source then
        apply_rules(source, "ui.popup.source", M.defaults.ui.popup.source, POPUP_SOURCE_RULES)
      end

      local history = as_table(popup.history)
      if history then
        apply_rules(history, "ui.popup.history", M.defaults.ui.popup.history, POPUP_HISTORY_RULES)
      end
    end

    local path = as_table(ui.path)
    if path then
      apply_rules(path, "ui.path", M.defaults.ui.path, UI_PATH_RULES)
    end

    if ui.stack_view ~= nil then
      local stack_view = ensure_table_field(ui, "stack_view", "ui.stack_view", M.defaults.ui.stack_view)
      if stack_view then
        apply_rules(stack_view, "ui.stack_view", M.defaults.ui.stack_view, STACK_VIEW_RULES)
      end
    end

    local inline_preview = as_table(ui.inline_preview)
    if inline_preview then
      apply_rules(inline_preview, "ui.inline_preview", M.defaults.ui.inline_preview, INLINE_PREVIEW_RULES)
    end

    local quick_peek = as_table(ui.quick_peek)
    if quick_peek then
      apply_rules(quick_peek, "ui.quick_peek", M.defaults.ui.quick_peek, QUICK_PEEK_RULES)
    end

    local title = as_table(ui.title)
    if title then
      if title.icons ~= nil and type(title.icons) ~= "table" then
        notify.warn("ui.title.icons must be a table, got " .. type(title.icons) .. ". Falling back to defaults")
        title.icons = vim.deepcopy(M.defaults.ui.title.icons)
      elseif type(title.icons) == "table" then
        local icons = title.icons
        apply_rules(icons, "ui.title.icons", M.defaults.ui.title.icons, TITLE_ICON_RULES)
        if icons.map ~= nil and type(icons.map) ~= "table" then
          notify.warn("ui.title.icons.map must be a table, got " .. type(icons.map) .. ". Falling back to defaults")
          icons.map = vim.deepcopy(M.defaults.ui.title.icons.map)
        end
      end
    end

    if ui.layout ~= nil then
      local layout = ensure_table_field(ui, "layout", "ui.layout", M.defaults.ui.layout)
      if layout then
        apply_rules(layout, "ui.layout", M.defaults.ui.layout, LAYOUT_RULES)

        if layout.min_size ~= nil then
          local min_size = ensure_table_field(layout, "min_size", "ui.layout.min_size", M.defaults.ui.layout.min_size)
          if min_size then
            apply_rules(min_size, "ui.layout.min_size", M.defaults.ui.layout.min_size, LAYOUT_MIN_SIZE_RULES)
          end
        end

        if layout.shrink ~= nil then
          local shrink = ensure_table_field(layout, "shrink", "ui.layout.shrink", M.defaults.ui.layout.shrink)
          if shrink then
            apply_rules(shrink, "ui.layout.shrink", M.defaults.ui.layout.shrink, LAYOUT_SHRINK_RULES)
          end
        end

        if layout.offset ~= nil then
          local offset = ensure_table_field(layout, "offset", "ui.layout.offset", M.defaults.ui.layout.offset)
          if offset then
            apply_rules(offset, "ui.layout.offset", M.defaults.ui.layout.offset, LAYOUT_OFFSET_RULES)
          end
        end
      end
    end
  end

  local picker = as_table(cfg.picker)
  if picker then
    apply_rules(picker, "picker", M.defaults.picker, PICKER_RULES)
  end

  local providers = as_table(cfg.providers)
  if providers then
    local marks = as_table(providers.marks)
    if marks then
      apply_rules(marks, "providers.marks", M.defaults.providers.marks, MARKS_RULES)
    end
  end

  local persist = as_table(cfg.persist)
  if persist then
    apply_rules(persist, "persist", M.defaults.persist, PERSIST_RULES)

    local session = as_table(persist.session)
    if session then
      apply_rules(session, "persist.session", M.defaults.persist.session, PERSIST_SESSION_RULES)
    end

    if persist.auto ~= nil then
      local auto = ensure_table_field(
        persist,
        "auto",
        "persist.auto",
        M.defaults.persist.auto,
        { fallback = false, message = "persist.auto must be a table" }
      )
      if auto then
        apply_rules(auto, "persist.auto", M.defaults.persist.auto, PERSIST_AUTO_RULES)
      end
    end
  end
end

---@param opts? PeekstackConfig
---@return PeekstackConfig
function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  validate(config)
  return config
end

---@return PeekstackConfig
function M.get()
  return config
end

return M
