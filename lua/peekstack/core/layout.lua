local config = require("peekstack.config")

local M = {}

---@class PeekstackLayoutResult
---@field width integer
---@field height integer
---@field row integer
---@field col integer
---@field zindex integer

---@param value number
---@param min number
---@param max number
---@return number
local function clamp(value, min, max)
  if value < min then
    return min
  end
  if value > max then
    return max
  end
  return value
end

---@param index integer
---@return PeekstackLayoutResult
function M.compute(index)
  local ui = config.get().ui
  local layout = ui.layout
  local columns = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight
  local max_w = math.floor(columns * layout.max_ratio)
  local max_h = math.floor(lines * layout.max_ratio)
  local base_width = clamp(max_w, layout.min_size.w, columns)
  local base_height = clamp(max_h, layout.min_size.h, lines)

  local step = index - 1
  local style = layout.style or "stack"
  local valid_styles = { stack = true, cascade = true, single = true }
  if not valid_styles[style] then
    style = "stack"
  end

  local width = base_width
  local height = base_height

  if style == "stack" then
    width = clamp(base_width - (layout.shrink.w * step), layout.min_size.w, columns)
    height = clamp(base_height - (layout.shrink.h * step), layout.min_size.h, lines)
  end

  local row = math.max(math.floor((lines - height) / 2), 0)
  local col = math.max(math.floor((columns - width) / 2), 0)

  if style == "stack" or style == "cascade" then
    row = row + (layout.offset.row * step)
    col = col + (layout.offset.col * step)
  end

  return {
    width = width,
    height = height,
    row = row,
    col = col,
    zindex = layout.zindex_base + step,
  }
end

---@param stack PeekstackStackModel
---@return integer?
local function focused_popup_winid(stack)
  local winid = vim.api.nvim_get_current_win()
  for _, popup in ipairs(stack.popups) do
    if popup.winid == winid then
      return winid
    end
  end
  return nil
end

---@param stack PeekstackStackModel
function M.reflow(stack)
  local focused_winid = focused_popup_winid(stack)
  local base = config.get().ui.layout.zindex_base
  local top = base + #stack.popups
  for idx, popup in ipairs(stack.popups) do
    if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
      local layout = M.compute(idx)
      local z = layout.zindex
      if focused_winid and popup.winid == focused_winid then
        z = top
      end
      local win_opts = vim.tbl_extend("force", popup.win_opts or {}, {
        row = layout.row,
        col = layout.col,
        width = layout.width,
        height = layout.height,
        zindex = z,
      })
      vim.api.nvim_win_set_config(popup.winid, win_opts)
    end
  end
end

---Temporarily raise the focused popup to the foreground while keeping
---all other popups at their natural zindex.  Uses the same layout
---computation as reflow so the config passed to nvim_win_set_config is
---always in a known-good format (avoids nvim_win_get_config round-trip
---issues across Neovim versions).
---@param stack PeekstackStackModel
---@param focused_winid integer
function M.update_focus_zindex(stack, focused_winid)
  local ui = config.get().ui
  local base = ui.layout.zindex_base
  local top = base + #stack.popups

  for idx, popup in ipairs(stack.popups) do
    if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
      local z = (popup.winid == focused_winid) and top or (base + idx - 1)
      local lo = M.compute(idx)
      local win_opts = vim.tbl_extend("force", popup.win_opts or {}, {
        row = lo.row,
        col = lo.col,
        width = lo.width,
        height = lo.height,
        zindex = z,
      })
      pcall(vim.api.nvim_win_set_config, popup.winid, win_opts)
    end
  end
end

return M
