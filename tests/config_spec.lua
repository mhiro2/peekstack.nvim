local config = require("peekstack.config")

describe("config", function()
  local original_notify = nil
  local notifications = {}

  -- Reset config before each test
  before_each(function()
    notifications = {}
    original_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
    config.setup({})
  end)

  after_each(function()
    vim.notify = original_notify
  end)

  describe("setup", function()
    it("returns defaults when called with no arguments", function()
      local cfg = config.setup()
      assert.equals("builtin", cfg.picker.backend)
      assert.equals("stack", cfg.ui.layout.style)
      assert.equals(true, cfg.ui.feedback.highlight_origin_on_close)
      assert.equals(false, cfg.persist.enabled)
    end)

    it("returns defaults when called with empty table", function()
      local cfg = config.setup({})
      assert.equals("builtin", cfg.picker.backend)
    end)

    it("merges user options with defaults", function()
      local cfg = config.setup({
        picker = { backend = "telescope" },
        persist = { enabled = true },
      })
      assert.equals("telescope", cfg.picker.backend)
      assert.equals(true, cfg.persist.enabled)
      assert.equals(1, cfg.picker.builtin.preview_lines) -- default preserved
    end)

    it("deeply merges nested tables", function()
      local cfg = config.setup({
        ui = {
          keys = { close = "x" },
        },
      })
      assert.equals("x", cfg.ui.keys.close)
      assert.equals("<C-j>", cfg.ui.keys.focus_next) -- default preserved
    end)

    it("config.get() returns the same config after setup", function()
      config.setup({ picker = { backend = "telescope" } })
      assert.equals("telescope", config.get().picker.backend)
    end)

    it("does not mutate defaults on subsequent setup calls", function()
      config.setup({ picker = { backend = "telescope" } })
      config.setup({})
      assert.equals("builtin", config.get().picker.backend)
    end)
  end)

  describe("defaults", function()
    it("has expected default key bindings", function()
      local keys = config.defaults.ui.keys
      assert.equals("q", keys.close)
      assert.equals("<C-j>", keys.focus_next)
      assert.equals("<C-k>", keys.focus_prev)
      assert.equals("<C-x>", keys.promote_split)
      assert.equals("<C-v>", keys.promote_vsplit)
      assert.equals("<C-t>", keys.promote_tab)
    end)

    it("has expected provider defaults", function()
      local providers = config.defaults.providers
      assert.is_true(providers.lsp.enable)
      assert.is_true(providers.diagnostics.enable)
      assert.is_true(providers.file.enable)
      assert.is_false(providers.marks.enable)
      assert.equals("all", providers.marks.scope)
      assert.equals("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", providers.marks.include)
      assert.is_false(providers.marks.include_special)
    end)

    it("has promote close_popup default", function()
      assert.is_true(config.defaults.ui.promote.close_popup)
    end)

    it("has popup editable default", function()
      assert.is_false(config.defaults.ui.popup.editable)
    end)

    it("has popup buffer_mode default", function()
      assert.equals("copy", config.defaults.ui.popup.buffer_mode)
    end)

    it("has popup source defaults", function()
      local source = config.defaults.ui.popup.source
      assert.is_true(source.prevent_auto_close_if_modified)
      assert.is_true(source.confirm_on_close)
    end)

    it("has popup history defaults", function()
      local history = config.defaults.ui.popup.history
      assert.equals(50, history.max_items)
      assert.equals("top", history.restore_position)
    end)

    it("has path display defaults", function()
      local path = config.defaults.ui.path
      assert.equals("repo", path.base)
      assert.equals(80, path.max_width)
    end)

    it("has persist auto defaults", function()
      local auto = config.defaults.persist.auto
      assert.is_false(auto.enabled)
      assert.equals("auto", auto.session_name)
      assert.is_true(auto.restore)
      assert.is_true(auto.save)
      assert.is_true(auto.restore_if_empty)
      assert.equals(1000, auto.debounce_ms)
      assert.is_true(auto.save_on_leave)
    end)
  end)

  describe("validation", function()
    local function has_message(pattern)
      for _, item in ipairs(notifications) do
        if item.msg:find(pattern, 1, true) then
          return true
        end
      end
      return false
    end

    it("falls back on invalid keymap types", function()
      local cfg = config.setup({
        ui = {
          keys = {
            close = 123,
            focus_next = false,
          },
        },
      })
      assert.is_true(has_message("ui.keys.close"))
      assert.is_true(has_message("ui.keys.focus_next"))
      assert.equals("q", cfg.ui.keys.close)
      assert.equals("<C-j>", cfg.ui.keys.focus_next)
    end)

    it("falls back on invalid layout values", function()
      local defaults = config.defaults.ui.layout
      local cfg = config.setup({
        ui = {
          layout = {
            max_ratio = 2,
            min_size = { w = -1, h = 0 },
            shrink = { w = -2, h = "x" },
            offset = { row = -1, col = "x" },
          },
        },
      })
      assert.is_true(has_message("ui.layout.max_ratio"))
      assert.is_true(has_message("ui.layout.min_size.w"))
      assert.is_true(has_message("ui.layout.min_size.h"))
      assert.is_true(has_message("ui.layout.shrink.w"))
      assert.is_true(has_message("ui.layout.shrink.h"))
      assert.is_true(has_message("ui.layout.offset.row"))
      assert.is_true(has_message("ui.layout.offset.col"))
      assert.equals(defaults.max_ratio, cfg.ui.layout.max_ratio)
      assert.equals(defaults.min_size.w, cfg.ui.layout.min_size.w)
      assert.equals(defaults.min_size.h, cfg.ui.layout.min_size.h)
      assert.equals(defaults.shrink.w, cfg.ui.layout.shrink.w)
      assert.equals(defaults.shrink.h, cfg.ui.layout.shrink.h)
      assert.equals(defaults.offset.row, cfg.ui.layout.offset.row)
      assert.equals(defaults.offset.col, cfg.ui.layout.offset.col)
    end)

    it("warns on invalid inline preview config", function()
      config.setup({
        ui = {
          inline_preview = {
            enabled = "yes",
            max_lines = "10",
            hl_group = 123,
            close_events = "CursorMoved",
          },
        },
      })
      assert.is_true(has_message("ui.inline_preview.enabled"))
      assert.is_true(has_message("ui.inline_preview.max_lines"))
      assert.is_true(has_message("ui.inline_preview.hl_group"))
      assert.is_true(has_message("ui.inline_preview.close_events"))
    end)

    it("warns on invalid quick peek config", function()
      config.setup({
        ui = {
          quick_peek = {
            close_events = { 1, 2 },
          },
        },
      })
      assert.is_true(has_message("ui.quick_peek.close_events"))
    end)

    it("warns on invalid path config", function()
      local cfg = config.setup({
        ui = {
          path = {
            base = "unknown",
            max_width = -1,
          },
        },
      })
      assert.is_true(has_message("ui.path.base"))
      assert.is_true(has_message("ui.path.max_width"))
      assert.equals("repo", cfg.ui.path.base)
      assert.equals(80, cfg.ui.path.max_width)
    end)

    it("warns on invalid persist session config", function()
      config.setup({
        persist = {
          session = {
            default_name = 1,
            prompt_if_missing = "yes",
          },
        },
      })
      assert.is_true(has_message("persist.session.default_name"))
      assert.is_true(has_message("persist.session.prompt_if_missing"))
    end)

    it("warns on invalid persist auto config", function()
      config.setup({
        persist = {
          auto = {
            enabled = "yes",
            session_name = 1,
            restore = "true",
            save = 1,
            restore_if_empty = "no",
            debounce_ms = "fast",
            save_on_leave = "maybe",
          },
        },
      })
      assert.is_true(has_message("persist.auto.enabled"))
      assert.is_true(has_message("persist.auto.session_name"))
      assert.is_true(has_message("persist.auto.restore"))
      assert.is_true(has_message("persist.auto.save"))
      assert.is_true(has_message("persist.auto.restore_if_empty"))
      assert.is_true(has_message("persist.auto.debounce_ms"))
      assert.is_true(has_message("persist.auto.save_on_leave"))
    end)

    it("falls back on invalid buffer_mode", function()
      local cfg = config.setup({
        ui = { popup = { buffer_mode = "invalid" } },
      })
      assert.is_true(has_message("ui.popup.buffer_mode"))
      assert.equals("copy", cfg.ui.popup.buffer_mode)
    end)

    it("accepts valid buffer_mode values", function()
      local cfg = config.setup({
        ui = { popup = { buffer_mode = "source" } },
      })
      assert.equals("source", cfg.ui.popup.buffer_mode)
    end)

    it("warns on invalid source config types", function()
      config.setup({
        ui = {
          popup = {
            source = {
              prevent_auto_close_if_modified = "yes",
              confirm_on_close = 1,
            },
          },
        },
      })
      assert.is_true(has_message("ui.popup.source.prevent_auto_close_if_modified"))
      assert.is_true(has_message("ui.popup.source.confirm_on_close"))
    end)

    it("warns on invalid history config types", function()
      config.setup({
        ui = {
          popup = {
            history = {
              max_items = "fifty",
            },
          },
        },
      })
      assert.is_true(has_message("ui.popup.history.max_items"))
    end)

    it("falls back on invalid restore_position", function()
      local cfg = config.setup({
        ui = { popup = { history = { restore_position = "invalid" } } },
      })
      assert.is_true(has_message("ui.popup.history.restore_position"))
      assert.equals("top", cfg.ui.popup.history.restore_position)
    end)

    it("merges popup source and history with defaults", function()
      local cfg = config.setup({
        ui = {
          popup = {
            source = { confirm_on_close = false },
            history = { max_items = 100 },
          },
        },
      })
      assert.is_false(cfg.ui.popup.source.confirm_on_close)
      assert.is_true(cfg.ui.popup.source.prevent_auto_close_if_modified) -- default preserved
      assert.equals(100, cfg.ui.popup.history.max_items)
      assert.equals("top", cfg.ui.popup.history.restore_position) -- default preserved
    end)
  end)
end)
