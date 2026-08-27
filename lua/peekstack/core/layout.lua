local config = require("peekstack.config")

local M = {}

---@class PeekstackLayoutResult
---@field width integer
---@field height integer
---@field row integer
---@field col integer
---@field zindex integer

---Border cells consumed by the popup border (one per side).
local BORDER_SIZE = 2

---Clamp a value into [min, max].  When min exceeds max (e.g. a configured
---min_size larger than the editor), max wins so the result always fits.
---@param value number
---@param min number
---@param max number
---@return number
local function clamp(value, min, max)
  if max < min then
    min = max
  end
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
  -- Usable area for the popup body: the border needs one cell on each side.
  local avail_w = math.max(columns - BORDER_SIZE, 1)
  local avail_h = math.max(lines - BORDER_SIZE, 1)
  local max_w = math.floor(columns * layout.max_ratio)
  local max_h = math.floor(lines * layout.max_ratio)
  local base_width = clamp(max_w, layout.min_size.w, avail_w)
  local base_height = clamp(max_h, layout.min_size.h, avail_h)

  local step = index - 1
  local style = layout.style or "stack"
  local valid_styles = { stack = true, cascade = true, single = true }
  if not valid_styles[style] then
    style = "stack"
  end

  local width = base_width
  local height = base_height

  if style == "stack" then
    width = clamp(base_width - (layout.shrink.w * step), layout.min_size.w, avail_w)
    height = clamp(base_height - (layout.shrink.h * step), layout.min_size.h, avail_h)
  end

  -- Maximum top-left position that still keeps the whole popup on screen.
  local max_row = math.max(lines - height - BORDER_SIZE, 0)
  local max_col = math.max(columns - width - BORDER_SIZE, 0)

  local row = math.floor(max_row / 2)
  local col = math.floor(max_col / 2)

  if style == "stack" or style == "cascade" then
    row = row + (layout.offset.row * step)
    col = col + (layout.offset.col * step)
  end

  row = clamp(row, 0, max_row)
  col = clamp(col, 0, max_col)

  return {
    width = width,
    height = height,
    row = row,
    col = col,
    zindex = layout.zindex_base + step,
  }
end

---Compute fullscreen layout for zoomed popup.
---@param popup_count integer  number of popups in the stack
---@return PeekstackLayoutResult
function M.compute_zoom(popup_count)
  local columns = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight
  local base = config.get().ui.layout.zindex_base
  return {
    width = math.max(columns - BORDER_SIZE, 1),
    height = math.max(lines - BORDER_SIZE, 1),
    row = 0,
    col = 0,
    zindex = base + popup_count + 1,
  }
end

---@param winid integer
---@param is_focused boolean
local function set_popup_winhighlight(winid, is_focused)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end
  vim.wo[winid].winhighlight = is_focused and "FloatBorder:PeekstackPopupBorderFocused"
    or "FloatBorder:PeekstackPopupBorder"
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

---@param winid integer
---@param is_zoomed boolean
local function set_popup_zoom_winhighlight(winid, is_zoomed)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end
  if is_zoomed then
    vim.wo[winid].winhighlight = "FloatBorder:PeekstackPopupBorderZoomed"
  end
end

---@param stack PeekstackStackModel
function M.reflow(stack)
  local focused_winid = focused_popup_winid(stack)
  local base = config.get().ui.layout.zindex_base
  local top = base + #stack.popups
  local zoomed_id = stack.zoomed_id
  for idx, popup in ipairs(stack.popups) do
    if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
      local is_focused = focused_winid ~= nil and popup.winid == focused_winid
      local is_zoomed = zoomed_id ~= nil and popup.id == zoomed_id

      local lo
      if is_zoomed then
        lo = M.compute_zoom(#stack.popups)
      else
        lo = M.compute(idx)
      end

      local z = lo.zindex
      if not is_zoomed and is_focused then
        z = top
      end
      local win_opts = vim.tbl_extend("force", popup.win_opts or {}, {
        row = lo.row,
        col = lo.col,
        width = lo.width,
        height = lo.height,
        zindex = z,
      })
      pcall(vim.api.nvim_win_set_config, popup.winid, win_opts)
      if is_zoomed then
        set_popup_zoom_winhighlight(popup.winid, true)
      else
        set_popup_winhighlight(popup.winid, is_focused)
      end
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
  local zoomed_id = stack.zoomed_id

  for idx, popup in ipairs(stack.popups) do
    if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
      local is_focused = popup.winid == focused_winid
      local is_zoomed = zoomed_id ~= nil and popup.id == zoomed_id

      local lo
      if is_zoomed then
        lo = M.compute_zoom(#stack.popups)
      else
        lo = M.compute(idx)
      end

      local z = lo.zindex
      if not is_zoomed and is_focused then
        z = top
      end
      local win_opts = vim.tbl_extend("force", popup.win_opts or {}, {
        row = lo.row,
        col = lo.col,
        width = lo.width,
        height = lo.height,
        zindex = z,
      })
      pcall(vim.api.nvim_win_set_config, popup.winid, win_opts)
      if is_zoomed then
        set_popup_zoom_winhighlight(popup.winid, true)
      else
        set_popup_winhighlight(popup.winid, is_focused)
      end
    end
  end
end

return M
