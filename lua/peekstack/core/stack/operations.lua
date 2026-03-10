local state = require("peekstack.core.stack.state")
local common = require("peekstack.core.stack.common")

local M = {}

local config, layout, popup, feedback, user_events, history
local function deps()
  if not config then
    config = require("peekstack.config")
    layout = require("peekstack.core.layout")
    popup = require("peekstack.core.popup")
    feedback = require("peekstack.ui.feedback")
    user_events = require("peekstack.core.user_events")
    history = require("peekstack.core.history")
  end
end

---@param opts table
---@return integer?
local function resolve_parent_popup_id(opts)
  if opts.parent_popup_id ~= nil then
    return opts.parent_popup_id
  end

  local current_win = vim.api.nvim_get_current_win()
  local owner = state.lookup_by_winid(current_win)
  if owner and owner.popup then
    return owner.popup.id
  end

  return nil
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
    M.focus_by_id(next_popup.id, stack.root_winid)
  end
end

---@param location PeekstackLocation
---@param opts? table
---@return PeekstackPopupModel?
function M.push(location, opts)
  deps()
  opts = opts or {}
  local defer_reflow = opts.defer_reflow == true
  local create_opts = vim.tbl_extend("force", {}, opts)
  create_opts.defer_reflow = nil
  create_opts.parent_popup_id = resolve_parent_popup_id(opts)

  if opts.stack == false then
    local model = popup.create(location, vim.tbl_extend("force", create_opts, { ephemeral = true }))
    if not model then
      return nil
    end
    state.register_ephemeral(model)

    local data = user_events.build_popup_data(model, vim.api.nvim_get_current_win(), { ephemeral = true })
    user_events.emit("PeekstackPush", data)

    return model
  end

  local stack = state.ensure_stack()
  if stack.hidden then
    M.toggle(stack.root_winid)
  end
  if stack.zoomed_id then
    stack.zoomed_id = nil
  end

  local model = popup.create(location, create_opts)
  if not model then
    return nil
  end
  table.insert(stack.popups, model)
  state.index_popup(model, stack.root_winid)
  stack.focused_id = model.id
  if not defer_reflow then
    layout.reflow(stack)
  end

  common.emit_popup_event("PeekstackPush", model, stack.root_winid)

  return model
end

---@param winid? integer
function M.reflow(winid)
  deps()
  layout.reflow(state.ensure_stack(winid))
end

---@param winid? integer
---@return PeekstackPopupModel[]
function M.list(winid)
  return state.ensure_stack(winid).popups
end

---@param winid? integer
---@return PeekstackPopupModel?
function M.current(winid)
  local stack = state.ensure_stack(winid)
  return stack.popups[#stack.popups]
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
  deps()
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

---@param winid? integer
---@return PeekstackPopupModel?
function M.restore_last(winid)
  deps()
  return history.restore_last(state.ensure_stack(winid))
end

---@param winid? integer
---@return PeekstackPopupModel[]
function M.restore_all(winid)
  deps()
  return history.restore_all(state.ensure_stack(winid))
end

---@param idx integer
---@param winid? integer
---@return PeekstackPopupModel?
function M.restore_from_history(idx, winid)
  deps()
  return history.restore_from_history(state.ensure_stack(winid), idx)
end

---@param winid? integer
---@return PeekstackHistoryEntry[]
function M.history_list(winid)
  return state.ensure_stack(winid).history
end

---@param winid? integer
function M.clear_history(winid)
  deps()
  history.clear(state.ensure_stack(winid))
end

---@return boolean
function M.close_current()
  local current = M.current()
  if current then
    return M.close(current.id)
  end
  return false
end

---@param winid integer
---@return PeekstackStackModel?, PeekstackPopupModel?
function M.find_by_winid(winid)
  local entry = state.lookup_by_winid(winid)
  if not entry then
    return nil
  end
  if entry.root_winid then
    local stack = state.stacks[entry.root_winid]
    if stack then
      return stack, entry.popup
    end
  end
  return nil, entry.popup
end

---@param id integer
---@return PeekstackPopupModel?
function M.find_by_id(id)
  local entry = state.lookup_by_id(id)
  if entry then
    return entry.popup
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

---@param step integer
---@return boolean
local function focus_relative(step)
  deps()
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

---@param id integer
---@param title string
---@param winid? integer
---@return boolean
function M.rename_by_id(id, title, winid)
  local stack = state.ensure_stack(winid)
  for _, item in ipairs(stack.popups) do
    if item.id == id then
      item.title = title
      item.title_chunks = nil
      return true
    end
  end
  return false
end

---@param id integer
---@param winid? integer
---@return boolean
function M.toggle_pin_by_id(id, winid)
  local stack = state.ensure_stack(winid)
  for _, item in ipairs(stack.popups) do
    if item.id == id then
      item.pinned = not item.pinned
      return true
    end
  end
  return false
end

---@param winid integer
function M.touch(winid)
  local owner_stack, popup_model = M.find_by_winid(winid)
  if owner_stack and popup_model then
    popup_model.last_active_at = vim.uv.now()
  end
end

---@param now_ms integer
---@param opts? { idle_ms: integer, ignore_pinned: boolean }
function M.close_stale(now_ms, opts)
  deps()
  opts = opts or {}
  local idle_ms = opts.idle_ms or 300000
  local ignore_pinned = opts.ignore_pinned ~= false
  local prevent_modified = config.get().ui.popup.source.prevent_auto_close_if_modified

  for root_winid, stack in pairs(state.stacks) do
    for idx = #stack.popups, 1, -1 do
      local item = stack.popups[idx]
      if (not ignore_pinned or not item.pinned) and item.last_active_at then
        local is_modified_source = prevent_modified
          and item.buffer_mode == "source"
          and vim.api.nvim_buf_is_valid(item.bufnr)
          and vim.bo[item.bufnr].modified

        if not is_modified_source then
          local idle_time = now_ms - item.last_active_at
          if idle_time > idle_ms then
            M.close(item.id, root_winid)
          end
        end
      end
    end
  end
end

function M.close_ephemerals()
  deps()
  for _, stack in pairs(state.stacks) do
    local removed = false
    for idx = #stack.popups, 1, -1 do
      local item = stack.popups[idx]
      if item.ephemeral then
        popup.close(item)
        state.unindex_popup(item)
        table.remove(stack.popups, idx)
        removed = true
      end
    end
    if removed then
      layout.reflow(stack)
    end
  end

  for id, item in pairs(state.ephemerals) do
    popup.close(item)
    state.unregister_ephemeral(id)
  end
end

function M.reflow_all()
  deps()
  for _, stack in pairs(state.stacks) do
    layout.reflow(stack)
  end
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
  else
    for idx, item in ipairs(stack.popups) do
      local model = common.reopen_popup(item, stack)
      if model then
        stack.popups[idx] = model
        state.index_popup(model, stack.root_winid)
      end
    end
    layout.reflow(stack)
    stack.hidden = false
    if stack.focused_id then
      M.focus_by_id(stack.focused_id, stack.root_winid)
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

---@param winid? integer
---@return integer?
function M.focused_id(winid)
  local stack = state.ensure_stack(winid)
  return stack.focused_id
end

return M
