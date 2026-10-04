local state = require("peekstack.core.stack.state")

local M = {}

local layout, popup, feedback, history, user_events
local function deps()
  if not popup then
    layout = require("peekstack.core.layout")
    popup = require("peekstack.core.popup")
    feedback = require("peekstack.ui.feedback")
    history = require("peekstack.core.history")
    user_events = require("peekstack.core.user_events")
  end
end

---@param event string
---@param popup_model PeekstackPopupModel
---@param root_winid integer
function M.emit_popup_event(event, popup_model, root_winid)
  deps()
  user_events.emit(event, user_events.build_popup_data(popup_model, root_winid))
end

---Re-create a popup window for an existing stack item.
---@param item PeekstackPopupModel
---@param stack PeekstackStackModel
---@return PeekstackPopupModel?
function M.reopen_popup(item, stack)
  deps()
  local reopen_opts = {
    id = item.id,
    buffer_mode = item.buffer_mode or "copy",
    origin_winid = stack.root_winid,
    parent_popup_id = item.parent_popup_id,
  }
  if not item.title_chunks then
    reopen_opts.title = item.title
  end
  local model = popup.create(item.location, reopen_opts)
  if not model then
    return nil
  end
  model.pinned = item.pinned or false
  return model
end

---Whether a popup belongs to its origin buffer and should close with it.
---Popups opened from another popup or the stack view outlive that buffer,
---which is wiped as soon as its window closes.
---@param item PeekstackPopupModel
---@return boolean
function M.closes_with_origin(item)
  return item.origin ~= nil and item.origin.bufnr ~= nil and item.origin_is_popup ~= true
end

---Remove a stack popup and record its close exactly once.
---The model is detached before the window closes, so the WinClosed autocmd
---triggered by the close no longer finds it. Decorations and source-mode
---keymaps are released even when the window is already gone.
---@param stack PeekstackStackModel
---@param idx integer
---@param item PeekstackPopupModel
---@param opts? { highlight_origin?: boolean }
function M.remove_stack_popup(stack, idx, item, opts)
  deps()
  table.remove(stack.popups, idx)
  state.unindex_popup(item)
  if stack.zoomed_id == item.id then
    stack.zoomed_id = nil
  end
  popup.close(item)
  if not opts or opts.highlight_origin ~= false then
    feedback.highlight_origin(item.origin)
  end
  M.emit_popup_event("PeekstackClose", item, stack.root_winid)
  history.push_entry(stack, history.build_entry(item, idx))
  user_events.emit("PeekstackHistoryPush", {
    popup_id = item.id,
    location = item.location,
    root_winid = stack.root_winid,
  })
end

---Remove every popup of `stack` matching `predicate`, top first. Targets are
---collected up front and looked up again before each removal, because
---closing one popup can wipe a buffer whose BufWipeout handler removes
---others in the meantime.
---@param stack PeekstackStackModel
---@param predicate fun(item: PeekstackPopupModel): boolean
---@param opts? { highlight_origin?: boolean }
---@return boolean removed
function M.remove_stack_popups(stack, predicate, opts)
  local targets = {}
  for idx = #stack.popups, 1, -1 do
    if predicate(stack.popups[idx]) then
      table.insert(targets, stack.popups[idx])
    end
  end
  for _, item in ipairs(targets) do
    for idx, current in ipairs(stack.popups) do
      if current == item then
        M.remove_stack_popup(stack, idx, item, opts)
        break
      end
    end
  end
  return #targets > 0
end

---Move focus to the top popup when the focused one was removed, then
---re-layout the remaining popups.
---@param stack PeekstackStackModel
function M.settle(stack)
  deps()
  if stack.focused_id ~= nil then
    local found = false
    for _, item in ipairs(stack.popups) do
      if item.id == stack.focused_id then
        found = true
        break
      end
    end
    if not found then
      local top = stack.popups[#stack.popups]
      stack.focused_id = top and top.id or nil
    end
  end
  layout.reflow(stack)
end

---Remove an ephemeral popup, releasing it the same way as stack popups.
---@param id integer
---@param item PeekstackPopupModel
---@param opts? { highlight_origin?: boolean }
function M.remove_ephemeral(id, item, opts)
  deps()
  local root_winid = state.ephemeral_root_winid(item)
  state.unregister_ephemeral(id)
  popup.close(item)
  if opts and opts.highlight_origin then
    feedback.highlight_origin(item.origin)
  end
  user_events.emit("PeekstackClose", user_events.build_popup_data(item, root_winid, { ephemeral = true }))
end

return M
