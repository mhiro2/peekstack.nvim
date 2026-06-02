local config = require("peekstack.config")
local location = require("peekstack.core.location")
local diff = require("peekstack.ui.stack_view.diff")
local pipeline = require("peekstack.ui.stack_view.pipeline")
local state = require("peekstack.ui.stack_view.state")

local M = {}

---@param s PeekstackStackViewState
---@param is_ready fun(s: PeekstackStackViewState): boolean
function M.render(s, is_ready)
  if not is_ready(s) then
    return
  end

  s.preview_ts_cache = s.preview_ts_cache or {}

  local stack = require("peekstack.core.stack")
  local items = stack.list(s.root_winid)
  local ui_path = config.get().ui.path or {}
  local repo_root_cache = ui_path.base == "repo" and {} or nil
  local win_width = vim.api.nvim_win_get_width(s.winid)
  if win_width <= 0 then
    win_width = vim.o.columns
  end

  local model = pipeline.build({
    items = items,
    focused_id = stack.focused_id(s.root_winid),
    filter = s.filter,
    win_width = win_width,
    ui_path = ui_path,
    location_text = function(popup, max_width)
      return location.display_text(popup.location, 0, {
        path_base = ui_path.base,
        max_width = max_width,
        repo_root_cache = repo_root_cache,
      })
    end,
  })

  s.line_to_id = model.line_to_id
  s.header_lines = model.header_lines
  s.render_keys = diff.apply(s.bufnr, s.render_keys or {}, model, s.preview_ts_cache)
  state.ensure_non_header_cursor(s)
end

return M
