local state = require("peekstack.core.stack.state")
local common = require("peekstack.core.stack.common")

local M = {}

local layout, popup, feedback, history, user_events
local function deps()
  if not layout then
    layout = require("peekstack.core.layout")
    popup = require("peekstack.core.popup")
    feedback = require("peekstack.ui.feedback")
    history = require("peekstack.core.history")
    user_events = require("peekstack.core.user_events")
  end
end

---@param stack PeekstackStackModel
---@param idx integer
---@param item PeekstackPopupModel
---@param opts? { close_window?: boolean, highlight_origin?: boolean }
local function remove_stack_popup(stack, idx, item, opts)
  opts = opts or {}
  if stack.zoomed_id == item.id then
    stack.zoomed_id = nil
  end
  if opts.highlight_origin ~= false then
    feedback.highlight_origin(item.origin)
  end
  common.emit_popup_event("PeekstackClose", item, stack.root_winid)
  history.push_entry(stack, history.build_entry(item, idx))
  user_events.emit("PeekstackHistoryPush", {
    popup_id = item.id,
    location = item.location,
    root_winid = stack.root_winid,
  })
  state.unindex_popup(item)
  table.remove(stack.popups, idx)
  if opts.close_window ~= false and item.winid and vim.api.nvim_win_is_valid(item.winid) then
    popup.close(item)
  end
end

---@param id integer
---@param item PeekstackPopupModel
---@param opts? { close_window?: boolean }
local function remove_ephemeral(id, item, opts)
  opts = opts or {}
  if opts.close_window ~= false and item.winid and vim.api.nvim_win_is_valid(item.winid) then
    popup.close(item)
  end
  state.unregister_ephemeral(id)
  user_events.emit(
    "PeekstackClose",
    user_events.build_popup_data(item, item.origin and item.origin.winid or 0, { ephemeral = true })
  )
end

---@param winid integer
function M.handle_win_closed(winid)
  deps()
  if state.suppress_win_events then
    return
  end
  if state.stack_view_wins[winid] then
    state.stack_view_wins[winid] = nil
    return
  end
  for id, item in pairs(state.ephemerals) do
    if item.winid == winid then
      user_events.emit("PeekstackClose", user_events.build_popup_data(item, item.origin and item.origin.winid or 0))
      state.unregister_ephemeral(id)
    end
  end
  for root_winid, stack in pairs(state.stacks) do
    if stack.root_winid == winid then
      for idx = #stack.popups, 1, -1 do
        local item = stack.popups[idx]
        common.emit_popup_event("PeekstackClose", item, root_winid)
        history.push_entry(stack, history.build_entry(item, idx))
        table.remove(stack.popups, idx)
        state.unindex_popup(item)
        popup.close(item)
      end
      state.stacks[root_winid] = nil
    else
      local removed = false
      local focused_removed = false
      for idx = #stack.popups, 1, -1 do
        local item = stack.popups[idx]
        if item.winid == winid then
          if stack.focused_id == item.id then
            focused_removed = true
          end
          if stack.zoomed_id == item.id then
            stack.zoomed_id = nil
          end
          common.emit_popup_event("PeekstackClose", item, root_winid)
          feedback.highlight_origin(item.origin)
          table.remove(stack.popups, idx)
          state.unindex_popup(item)
          popup.close(item)
          removed = true
        end
      end
      if removed then
        if focused_removed then
          if #stack.popups > 0 then
            stack.focused_id = stack.popups[#stack.popups].id
          else
            stack.focused_id = nil
          end
        end
        layout.reflow(stack)
      end
    end
  end
end

---@param bufnr integer
function M.handle_buf_wipeout(bufnr)
  deps()
  if state.suppress_win_events then
    return
  end
  for id, item in pairs(state.ephemerals) do
    if item.bufnr == bufnr then
      remove_ephemeral(id, item, { close_window = false })
    end
  end
  for _, stack in pairs(state.stacks) do
    local removed = false
    local focused_removed = false
    for idx = #stack.popups, 1, -1 do
      local item = stack.popups[idx]
      if item.bufnr == bufnr then
        if stack.focused_id == item.id then
          focused_removed = true
        end
        remove_stack_popup(stack, idx, item, { close_window = false })
        removed = true
      end
    end
    if removed then
      if focused_removed then
        if #stack.popups > 0 then
          stack.focused_id = stack.popups[#stack.popups].id
        else
          stack.focused_id = nil
        end
      end
      layout.reflow(stack)
    end
  end
end

---@param bufnr integer
function M.handle_origin_wipeout(bufnr)
  deps()
  local function should_close_for_origin(item)
    if not (item.origin and item.origin.bufnr == bufnr) then
      return false
    end
    if item.origin_is_popup == true then
      return false
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      local ft = vim.bo[bufnr].filetype
      if ft == "peekstack-stack" or ft == "peekstack-stack-help" then
        return false
      end
    end
    return true
  end
  for id, item in pairs(state.ephemerals) do
    if should_close_for_origin(item) then
      remove_ephemeral(id, item)
    end
  end
  for _, stack in pairs(state.stacks) do
    local removed = false
    local focused_removed = false
    for idx = #stack.popups, 1, -1 do
      local item = stack.popups[idx]
      if should_close_for_origin(item) then
        if stack.focused_id == item.id then
          focused_removed = true
        end
        remove_stack_popup(stack, idx, item)
        removed = true
      end
    end
    if removed then
      if focused_removed then
        if #stack.popups > 0 then
          stack.focused_id = stack.popups[#stack.popups].id
        else
          stack.focused_id = nil
        end
      end
      layout.reflow(stack)
    end
  end
end

return M
