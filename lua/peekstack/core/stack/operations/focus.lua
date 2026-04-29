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

---@param id integer
---@param winid? integer
---@return PeekstackPopupModel?
function M.reopen_by_id(id, winid)
  deps()
  local stack = state.ensure_stack(winid)
  for idx, item in ipairs(stack.popups) do
    if item.id == id then
      local model = common.reopen_popup(item, stack)
      if not model then
        return nil
      end
      state.unindex_popup(item)
      stack.popups[idx] = model
      state.index_popup(model, stack.root_winid)
      layout.reflow(stack)
      return model
    end
  end
  return nil
end

---@param id integer
---@param winid? integer
---@return boolean
function M.focus_by_id(id, winid)
  deps()
  local stack = state.ensure_stack(winid)
  for _, item in ipairs(stack.popups) do
    if item.id == id or item.winid == id then
      local target = item
      local ok = popup.focus(target)
      if not ok then
        local reopened = M.reopen_by_id(item.id, stack.root_winid)
        if reopened then
          target = reopened
          ok = popup.focus(reopened)
        end
      end
      if ok then
        stack.focused_id = target.id
        layout.update_focus_zindex(stack, target.winid)
        common.emit_popup_event("PeekstackFocus", target, stack.root_winid)
      end
      return ok
    end
  end
  return false
end

---@param step integer
---@return boolean
local function focus_relative(step)
  local stack = state.ensure_stack()
  local count = #stack.popups
  if count == 0 then
    return false
  end
  local current_win = vim.api.nvim_get_current_win()
  local idx = 0
  for i, item in ipairs(stack.popups) do
    if item.winid == current_win then
      idx = i
      break
    end
  end
  local next_idx = ((idx + step - 1) % count) + 1
  local target = stack.popups[next_idx]
  return M.focus_by_id(target.id, stack.root_winid)
end

---@return boolean
function M.focus_next()
  return focus_relative(1)
end

---@return boolean
function M.focus_prev()
  return focus_relative(-1)
end

return M
