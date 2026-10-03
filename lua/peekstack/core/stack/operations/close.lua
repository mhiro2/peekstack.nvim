local state = require("peekstack.core.stack.state")
local common = require("peekstack.core.stack.common")

local M = {}

---@param stack PeekstackStackModel
---@param idx integer
---@param item PeekstackPopupModel
local function close_stack_item(stack, idx, item)
  local current_win = vim.api.nvim_get_current_win()
  local should_restore_focus = item.winid == current_win and vim.w[current_win].peekstack_popup_id ~= nil
  common.remove_stack_popup(stack, idx, item)
  common.settle(stack)

  if should_restore_focus and #stack.popups > 0 then
    local next_popup = stack.popups[#stack.popups]
    require("peekstack.core.stack.operations.focus").focus_by_id(next_popup.id, stack.root_winid)
  end
end

---@param id integer
---@param winid? integer
---@return boolean
function M.close_by_id(id, winid)
  local ephemeral_id, ephemeral = state.find_ephemeral(id)
  if ephemeral_id and ephemeral then
    common.remove_ephemeral(ephemeral_id, ephemeral, { highlight_origin = true })
    return true
  end

  local indexed = state.lookup_by_id(id)
  if indexed and indexed.root_winid then
    local owner_stack = state.stacks[indexed.root_winid]
    if owner_stack then
      for idx, item in ipairs(owner_stack.popups) do
        if item.id == id then
          close_stack_item(owner_stack, idx, item)
          return true
        end
      end
    end
  end

  local stack = state.ensure_stack(winid)
  for idx, item in ipairs(stack.popups) do
    if item.id == id then
      close_stack_item(stack, idx, item)
      return true
    end
  end
  return false
end

---@param id integer
---@param winid? integer
---@return boolean
function M.close(id, winid)
  if M.close_by_id(id, winid) then
    return true
  end

  local indexed = state.lookup_by_winid(id)
  if indexed and indexed.root_winid then
    local owner_stack = state.stacks[indexed.root_winid]
    if owner_stack then
      for idx, item in ipairs(owner_stack.popups) do
        if item.winid == id then
          close_stack_item(owner_stack, idx, item)
          return true
        end
      end
    end
  end

  local stack = state.ensure_stack(winid)
  for idx, item in ipairs(stack.popups) do
    if item.winid == id then
      close_stack_item(stack, idx, item)
      return true
    end
  end
  return false
end

---@return boolean
function M.close_current()
  local query = require("peekstack.core.stack.operations.query")
  local current = query.current()
  if current then
    return M.close(current.id)
  end
  return false
end

---@param winid? integer
function M.close_all(winid)
  local stack = state.ensure_stack(winid)
  -- Hidden popups have no window, so there is no origin to point back to.
  local highlight_origin = not stack.hidden
  common.remove_stack_popups(stack, function()
    return true
  end, { highlight_origin = highlight_origin })
  stack.zoomed_id = nil
  stack.hidden = false
  stack.focused_id = nil
end

return M
