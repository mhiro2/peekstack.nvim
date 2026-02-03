local M = {}

---Resolve the provider context from the current window/buffer state.
---If called from inside a popup, the context translates the cursor position
---back to the source buffer coordinate space.
---@return PeekstackProviderContext
function M.current()
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local cursor = vim.api.nvim_win_get_cursor(winid) -- {1-indexed line, 0-indexed col}

  local popup_id = vim.w[winid].peekstack_popup_id
  if popup_id then
    local stack = require("peekstack.core.stack")
    local stack_model, popup_model = stack.find_by_winid(winid)

    if popup_model then
      local line_offset = popup_model.line_offset or 0
      local source_bufnr = popup_model.source_bufnr
      local source_line = (cursor[1] - 1) + line_offset
      local source_col = cursor[2]

      local root_winid
      if stack_model then
        root_winid = stack_model.root_winid
      else
        root_winid = popup_model.origin and popup_model.origin.winid or winid
      end

      return {
        winid = winid,
        bufnr = source_bufnr,
        source_bufnr = source_bufnr,
        popup_id = popup_model.id,
        buffer_mode = popup_model.buffer_mode,
        line_offset = line_offset,
        position = { line = source_line, character = source_col },
        root_winid = root_winid,
        from_popup = true,
      }
    end
  end

  -- Normal window (not a popup)
  local stack = require("peekstack.core.stack")
  local s = stack.current_stack(winid)

  return {
    winid = winid,
    bufnr = bufnr,
    source_bufnr = nil,
    popup_id = nil,
    buffer_mode = nil,
    line_offset = 0,
    position = { line = cursor[1] - 1, character = cursor[2] },
    root_winid = s.root_winid,
    from_popup = false,
  }
end

return M
