local state = require("peekstack.core.stack.state")
local common = require("peekstack.core.stack.common")

local M = {}

local layout, popup, feedback, user_events, history
local function deps()
  if not layout then
    layout = require("peekstack.core.layout")
    popup = require("peekstack.core.popup")
    feedback = require("peekstack.ui.feedback")
    user_events = require("peekstack.core.user_events")
    history = require("peekstack.core.history")
  end
end

---@param stack PeekstackStackModel
---@param idx integer
---@param item PeekstackPopupModel
local function close_stack_item(stack, idx, item)
  deps()
  local current_win = vim.api.nvim_get_current_win()
  local should_restore_focus = item.winid == current_win and vim.w[current_win].peekstack_popup_id ~= nil
  if stack.zoomed_id == item.id then
    stack.zoomed_id = nil
  end
  table.remove(stack.popups, idx)
  state.unindex_popup(item)

  feedback.highlight_origin(item.origin)
  popup.close(item)

  common.emit_popup_event("PeekstackClose", item, stack.root_winid)

  history.push_entry(stack, history.build_entry(item, idx))

  user_events.emit("PeekstackHistoryPush", {
    popup_id = item.id,
    location = item.location,
    root_winid = stack.root_winid,
  })

  layout.reflow(stack)

  if stack.focused_id == item.id then
    if #stack.popups > 0 then
      stack.focused_id = stack.popups[#stack.popups].id
    else
      stack.focused_id = nil
    end
  end

  if should_restore_focus and #stack.popups > 0 then
    local next_popup = stack.popups[#stack.popups]
    require("peekstack.core.stack.operations.focus").focus_by_id(next_popup.id, stack.root_winid)
  end
end

---@param id integer
---@param winid? integer
---@return boolean
function M.close_by_id(id, winid)
  deps()
  local ephemeral_id, ephemeral = state.find_ephemeral(id)
  if ephemeral_id and ephemeral then
    feedback.highlight_origin(ephemeral.origin)
    popup.close(ephemeral)
    state.unregister_ephemeral(ephemeral_id)

    user_events.emit(
      "PeekstackClose",
      user_events.build_popup_data(ephemeral, ephemeral.origin and ephemeral.origin.winid or 0)
    )

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
  deps()
  local stack = state.ensure_stack(winid)
  stack.zoomed_id = nil
  if stack.hidden then
    for idx = #stack.popups, 1, -1 do
      local item = stack.popups[idx]
      common.emit_popup_event("PeekstackClose", item, stack.root_winid)
      history.push_entry(stack, history.build_entry(item, idx))
      state.unindex_popup(item)
      table.remove(stack.popups, idx)
    end
    stack.hidden = false
    stack.focused_id = nil
    return
  end
  for idx = #stack.popups, 1, -1 do
    local item = stack.popups[idx]
    feedback.highlight_origin(item.origin)
    popup.close(item)

    common.emit_popup_event("PeekstackClose", item, stack.root_winid)

    history.push_entry(stack, history.build_entry(item, idx))

    state.unindex_popup(item)
    table.remove(stack.popups, idx)
  end
  stack.focused_id = nil
end

return M
