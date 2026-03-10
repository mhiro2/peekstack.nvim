local DEFAULT_CLOSE_EVENTS = { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" }

---@type PeekstackConfig
return {
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
      zoom = "<C-z>",
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
