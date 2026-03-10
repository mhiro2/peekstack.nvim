local M = {}

---@class PeekstackPopupOriginCapture
---@field winid integer
---@field bufnr integer
---@field row integer
---@field col integer
---@field is_popup boolean

---@param winid integer
---@return PeekstackPopupOriginCapture
local function capture_from_win(winid)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local cursor = vim.api.nvim_win_get_cursor(winid)
  return {
    winid = winid,
    bufnr = bufnr,
    row = cursor[1],
    col = cursor[2],
    is_popup = vim.w[winid].peekstack_popup_id ~= nil,
  }
end

---@param winid? integer
---@return PeekstackPopupOriginCapture
function M.capture(winid)
  if winid and vim.api.nvim_win_is_valid(winid) then
    return capture_from_win(winid)
  end
  return capture_from_win(vim.api.nvim_get_current_win())
end

---@param origin PeekstackPopupOriginCapture
---@return boolean
function M.is_popup_origin(origin)
  if
    origin.is_popup == true
    and vim.api.nvim_buf_is_valid(origin.bufnr)
    and vim.bo[origin.bufnr].buftype == "nofile"
    and vim.bo[origin.bufnr].bufhidden == "wipe"
  then
    return true
  end

  if vim.api.nvim_buf_is_valid(origin.bufnr) then
    local ft = vim.bo[origin.bufnr].filetype
    return ft == "peekstack-stack" or ft == "peekstack-stack-help"
  end

  return false
end

return M
