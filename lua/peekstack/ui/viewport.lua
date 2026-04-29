local M = {}

local NS = vim.api.nvim_create_namespace("peekstack_viewport")

---@class PeekstackViewportExtmarks
---@field bufnr integer
---@field ns integer
---@field ids integer[]

---@param count integer
---@param direction "above"|"below"
---@return string
local function format_marker(count, direction)
  local arrow = direction == "above" and "↑" or "↓"
  local label = direction == "above" and "earlier" or "later"
  local plural = count == 1 and "line" or "lines"
  return string.format("%s %d %s %s hidden", arrow, count, label, plural)
end

---Decorate a popup buffer with virt_lines markers describing how many lines
---are hidden above and below the visible viewport. Returns nil for popups
---whose buffer reflects the full source (no truncation, source mode, etc.).
---@param popup PeekstackPopupModel
---@return PeekstackViewportExtmarks?
function M.decorate(popup)
  if not popup or popup.buffer_mode ~= "copy" then
    return nil
  end

  local viewport = popup.viewport
  if not viewport then
    return nil
  end

  local bufnr = popup.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return nil
  end

  local ids = {}

  if viewport.skipped_before and viewport.skipped_before > 0 then
    local id = vim.api.nvim_buf_set_extmark(bufnr, NS, 0, 0, {
      virt_lines = { { { format_marker(viewport.skipped_before, "above"), "PeekstackViewportTruncated" } } },
      virt_lines_above = true,
    })
    ids[#ids + 1] = id
  end

  if viewport.skipped_after and viewport.skipped_after > 0 then
    local last = line_count - 1
    local id = vim.api.nvim_buf_set_extmark(bufnr, NS, last, 0, {
      virt_lines = { { { format_marker(viewport.skipped_after, "below"), "PeekstackViewportTruncated" } } },
    })
    ids[#ids + 1] = id
  end

  if #ids == 0 then
    return nil
  end

  return { bufnr = bufnr, ns = NS, ids = ids }
end

---@param marks PeekstackViewportExtmarks?
function M.clear(marks)
  if not marks or not marks.bufnr then
    return
  end
  if not vim.api.nvim_buf_is_valid(marks.bufnr) then
    return
  end
  for _, id in ipairs(marks.ids or {}) do
    pcall(vim.api.nvim_buf_del_extmark, marks.bufnr, marks.ns, id)
  end
end

return M
