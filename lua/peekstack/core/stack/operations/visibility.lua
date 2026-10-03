local state = require("peekstack.core.stack.state")
local common = require("peekstack.core.stack.common")

local M = {}

local layout, popup
local function deps()
  if not layout then
    layout = require("peekstack.core.layout")
    popup = require("peekstack.core.popup")
  end
end

---@param winid? integer
function M.reflow(winid)
  deps()
  layout.reflow(state.ensure_stack(winid))
end

function M.reflow_all()
  deps()
  for _, stack in pairs(state.stacks) do
    layout.reflow(stack)
  end
end

---@param stack PeekstackStackModel
local function hide(stack)
  stack.zoomed_id = nil
  if vim.api.nvim_win_is_valid(stack.root_winid) then
    vim.api.nvim_set_current_win(stack.root_winid)
  end
  state.suppress_win_events = true
  for _, item in ipairs(stack.popups) do
    popup.close(item)
    state.unindex_popup(item)
    item.winid = nil
  end
  state.suppress_win_events = false
  stack.hidden = true
end

---Show a hidden stack without moving focus. Popups that already have a live
---window keep it, so no window is ever opened twice for one popup.
---Every operation that opens or focuses a popup calls this first.
---@param stack PeekstackStackModel
function M.show(stack)
  deps()
  if not stack.hidden then
    return
  end
  stack.hidden = false
  for idx, item in ipairs(stack.popups) do
    if not (item.winid and vim.api.nvim_win_is_valid(item.winid)) then
      local model = common.reopen_popup(item, stack)
      if model then
        stack.popups[idx] = model
        state.index_popup(model, stack.root_winid)
      end
    end
  end
  layout.reflow(stack)
end

---@param winid? integer
---@return boolean
function M.toggle(winid)
  deps()
  local stack = state.ensure_stack(winid)
  if #stack.popups == 0 then
    return false
  end

  if not stack.hidden then
    hide(stack)
  else
    M.show(stack)
    if stack.focused_id then
      require("peekstack.core.stack.operations.focus").focus_by_id(stack.focused_id, stack.root_winid)
    end
  end
  return true
end

---@param winid? integer
---@return boolean
function M.is_hidden(winid)
  local stack = state.ensure_stack(winid)
  return stack.hidden == true
end

---@param winid? integer
---@return boolean
function M.toggle_zoom(winid)
  deps()
  local stack = state.ensure_stack(winid)
  if #stack.popups == 0 or stack.hidden then
    return false
  end

  local top = stack.popups[#stack.popups]
  if stack.zoomed_id == top.id then
    stack.zoomed_id = nil
  else
    stack.zoomed_id = top.id
  end
  layout.reflow(stack)
  return true
end

---@param winid? integer
---@return boolean
function M.is_zoomed(winid)
  local stack = state.ensure_stack(winid)
  return stack.zoomed_id ~= nil
end

return M
