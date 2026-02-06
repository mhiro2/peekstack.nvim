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

---@param path string
---@param expected_type string
---@param value any
local function validate_type(path, expected_type, value)
  if type(value) ~= expected_type then
    notify.warn(string.format("%s must be a %s, got %s", path, expected_type, type(value)))
  end
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
      format = "{kind}{provider} {path}:{line}{context}",
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

---@param cfg table
local function validate(cfg)
  if cfg.ui and cfg.ui.keys ~= nil then
    if type(cfg.ui.keys) ~= "table" then
      notify.warn(string.format("ui.keys must be a table, got %s. Falling back to defaults", type(cfg.ui.keys)))
      cfg.ui.keys = vim.deepcopy(M.defaults.ui.keys)
    else
      local defaults = M.defaults.ui.keys
      for name, val in pairs(cfg.ui.keys) do
        if type(val) ~= "string" then
          notify.warn(
            string.format(
              "ui.keys.%s must be a string, got %s. Falling back to %s",
              name,
              type(val),
              tostring(defaults[name])
            )
          )
          cfg.ui.keys[name] = defaults[name]
        end
      end
    end
  end

  if cfg.ui and cfg.ui.popup and cfg.ui.popup.editable ~= nil then
    validate_type("ui.popup.editable", "boolean", cfg.ui.popup.editable)
  end

  if cfg.ui and cfg.ui.path then
    local path = cfg.ui.path
    if path.base then
      path.base = validate_enum("ui.path.base", path.base, KNOWN_PATH_BASES, M.defaults.ui.path.base)
    end
    if path.max_width ~= nil then
      if type(path.max_width) ~= "number" then
        notify.warn(string.format("ui.path.max_width must be a number, got %s", type(path.max_width)))
      elseif path.max_width < 0 then
        notify.warn(string.format("ui.path.max_width must be >= 0, got %s", path.max_width))
        path.max_width = M.defaults.ui.path.max_width
      end
    end
  end

  -- Validate buffer_mode
  if cfg.ui and cfg.ui.popup and cfg.ui.popup.buffer_mode then
    cfg.ui.popup.buffer_mode = validate_enum(
      "ui.popup.buffer_mode",
      cfg.ui.popup.buffer_mode,
      KNOWN_BUFFER_MODES,
      M.defaults.ui.popup.buffer_mode
    )
  end

  -- Validate source mode settings
  if cfg.ui and cfg.ui.popup and cfg.ui.popup.source then
    local source = cfg.ui.popup.source
    if source.prevent_auto_close_if_modified ~= nil then
      validate_type("ui.popup.source.prevent_auto_close_if_modified", "boolean", source.prevent_auto_close_if_modified)
    end
    if source.confirm_on_close ~= nil then
      validate_type("ui.popup.source.confirm_on_close", "boolean", source.confirm_on_close)
    end
  end

  -- Validate history settings
  if cfg.ui and cfg.ui.popup and cfg.ui.popup.history then
    local history = cfg.ui.popup.history
    if history.max_items ~= nil then
      history.max_items = validate_number_range(
        "ui.popup.history.max_items",
        history.max_items,
        M.defaults.ui.popup.history.max_items,
        { min = 1 }
      )
    end
    if history.restore_position then
      history.restore_position = validate_enum(
        "ui.popup.history.restore_position",
        history.restore_position,
        KNOWN_RESTORE_POSITIONS,
        M.defaults.ui.popup.history.restore_position
      )
    end
  end

  if cfg.ui and cfg.ui.inline_preview then
    local inline_preview = cfg.ui.inline_preview
    if inline_preview.enabled ~= nil then
      validate_type("ui.inline_preview.enabled", "boolean", inline_preview.enabled)
    end
    if inline_preview.max_lines ~= nil then
      inline_preview.max_lines = validate_number_range(
        "ui.inline_preview.max_lines",
        inline_preview.max_lines,
        M.defaults.ui.inline_preview.max_lines,
        { min = 1 }
      )
    end
    if inline_preview.hl_group ~= nil then
      validate_type("ui.inline_preview.hl_group", "string", inline_preview.hl_group)
    end
    if inline_preview.close_events ~= nil then
      validate_event_list("ui.inline_preview.close_events", inline_preview.close_events)
    end
  end

  if cfg.ui and cfg.ui.quick_peek then
    local quick_peek = cfg.ui.quick_peek
    if quick_peek.close_events ~= nil then
      validate_event_list("ui.quick_peek.close_events", quick_peek.close_events)
    end
  end

  -- Validate picker backend (fallback to default on invalid value)
  if cfg.picker and cfg.picker.backend then
    cfg.picker.backend = validate_enum("picker.backend", cfg.picker.backend, KNOWN_BACKENDS, M.defaults.picker.backend)
  end

  -- Validate layout style (fallback to default on invalid value)
  if cfg.ui and cfg.ui.layout ~= nil then
    if type(cfg.ui.layout) ~= "table" then
      notify.warn(string.format("ui.layout must be a table, got %s. Falling back to defaults", type(cfg.ui.layout)))
      cfg.ui.layout = vim.deepcopy(M.defaults.ui.layout)
    else
      local layout = cfg.ui.layout
      if layout.style then
        layout.style = validate_enum("ui.layout.style", layout.style, KNOWN_LAYOUT_STYLES, M.defaults.ui.layout.style)
      end
      if layout.max_ratio ~= nil then
        layout.max_ratio = validate_ratio("ui.layout.max_ratio", layout.max_ratio, M.defaults.ui.layout.max_ratio)
      end
      if layout.min_size ~= nil then
        if type(layout.min_size) ~= "table" then
          notify.warn(
            string.format("ui.layout.min_size must be a table, got %s. Falling back to defaults", type(layout.min_size))
          )
          layout.min_size = vim.deepcopy(M.defaults.ui.layout.min_size)
        else
          layout.min_size.w =
            validate_number_range("ui.layout.min_size.w", layout.min_size.w, M.defaults.ui.layout.min_size.w, {
              min = 1,
            })
          layout.min_size.h =
            validate_number_range("ui.layout.min_size.h", layout.min_size.h, M.defaults.ui.layout.min_size.h, {
              min = 1,
            })
        end
      end
      if layout.shrink ~= nil then
        if type(layout.shrink) ~= "table" then
          notify.warn(
            string.format("ui.layout.shrink must be a table, got %s. Falling back to defaults", type(layout.shrink))
          )
          layout.shrink = vim.deepcopy(M.defaults.ui.layout.shrink)
        else
          layout.shrink.w =
            validate_number_range("ui.layout.shrink.w", layout.shrink.w, M.defaults.ui.layout.shrink.w, { min = 0 })
          layout.shrink.h =
            validate_number_range("ui.layout.shrink.h", layout.shrink.h, M.defaults.ui.layout.shrink.h, { min = 0 })
        end
      end
      if layout.offset ~= nil then
        if type(layout.offset) ~= "table" then
          notify.warn(
            string.format("ui.layout.offset must be a table, got %s. Falling back to defaults", type(layout.offset))
          )
          layout.offset = vim.deepcopy(M.defaults.ui.layout.offset)
        else
          layout.offset.row = validate_number_range(
            "ui.layout.offset.row",
            layout.offset.row,
            M.defaults.ui.layout.offset.row,
            { min = 0 }
          )
          layout.offset.col = validate_number_range(
            "ui.layout.offset.col",
            layout.offset.col,
            M.defaults.ui.layout.offset.col,
            { min = 0 }
          )
        end
      end
    end
  end

  -- Validate marks provider settings
  if cfg.providers and cfg.providers.marks then
    local marks = cfg.providers.marks
    if marks.scope then
      marks.scope =
        validate_enum("providers.marks.scope", marks.scope, KNOWN_MARK_SCOPES, M.defaults.providers.marks.scope)
    end
    if marks.include ~= nil then
      validate_type("providers.marks.include", "string", marks.include)
    end
    if marks.include_special ~= nil then
      validate_type("providers.marks.include_special", "boolean", marks.include_special)
    end
  end

  if cfg.persist and cfg.persist.max_items ~= nil then
    cfg.persist.max_items =
      validate_number_range("persist.max_items", cfg.persist.max_items, M.defaults.persist.max_items, { min = 1 })
  end

  if cfg.persist and cfg.persist.session then
    local session = cfg.persist.session
    if session.default_name ~= nil then
      validate_type("persist.session.default_name", "string", session.default_name)
    end
    if session.prompt_if_missing ~= nil then
      validate_type("persist.session.prompt_if_missing", "boolean", session.prompt_if_missing)
    end
  end

  if cfg.persist and cfg.persist.auto ~= nil then
    if type(cfg.persist.auto) ~= "table" then
      notify.warn("persist.auto must be a table")
    else
      local auto = cfg.persist.auto
      if auto.enabled ~= nil then
        validate_type("persist.auto.enabled", "boolean", auto.enabled)
      end
      if auto.session_name ~= nil then
        validate_type("persist.auto.session_name", "string", auto.session_name)
      end
      if auto.restore ~= nil then
        validate_type("persist.auto.restore", "boolean", auto.restore)
      end
      if auto.save ~= nil then
        validate_type("persist.auto.save", "boolean", auto.save)
      end
      if auto.restore_if_empty ~= nil then
        validate_type("persist.auto.restore_if_empty", "boolean", auto.restore_if_empty)
      end
      if auto.debounce_ms ~= nil then
        validate_type("persist.auto.debounce_ms", "number", auto.debounce_ms)
      end
      if auto.save_on_leave ~= nil then
        validate_type("persist.auto.save_on_leave", "boolean", auto.save_on_leave)
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
