local config = require("peekstack.config")

local M = {}
local ns = vim.api.nvim_create_namespace("peekstack_origin")

---Highlight the origin location when a popup is closed
---@param origin? { winid: integer, bufnr: integer, row?: integer, col?: integer }
function M.highlight_origin(origin)
  if not config.get().ui.feedback.highlight_origin_on_close then
    return
  end
  if not origin or not origin.winid or not vim.api.nvim_win_is_valid(origin.winid) then
    return
  end
  local bufnr = origin.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local row = math.max((origin.row or 1) - 1, 0)
  vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
    end_row = row + 1,
    hl_group = "PeekstackOrigin",
  })
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, row, row + 1)
    end
  end, 250)
end

return M
