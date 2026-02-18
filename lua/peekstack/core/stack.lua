local M = {}

-- Lazy-loaded dependencies (deferred until first peek to avoid loading all
-- modules when stack.lua is first required).
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

---@param event string
---@param popup_model PeekstackPopupModel
---@param root_winid integer
local function emit_popup_event(event, popup_model, root_winid)
  deps()
  user_events.emit(event, user_events.build_popup_data(popup_model, root_winid))
end

---@type table<integer, PeekstackStackModel>
local stacks = {}
---@type table<integer, PeekstackPopupModel>
local ephemerals = {}
---@type table<integer, boolean>
local stack_view_wins = {}
---@class PeekstackPopupLookupEntry
---@field popup PeekstackPopupModel
---@field root_winid integer?
---@type table<integer, PeekstackPopupLookupEntry>
local popup_by_id = {}
---@type table<integer, PeekstackPopupLookupEntry>
local popup_by_winid = {}

---@param model PeekstackPopupModel
local function unindex_popup(model)
  if not model then
    return
  end

  local removed = false

  local id = model.id
  if id ~= nil then
    local entry_by_id = popup_by_id[id]
    if entry_by_id and entry_by_id.popup == model then
      popup_by_id[id] = nil
      removed = true
    end
  end

  local winid = model.winid
  if winid ~= nil then
    local entry_by_winid = popup_by_winid[winid]
    if entry_by_winid and entry_by_winid.popup == model then
      popup_by_winid[winid] = nil
      removed = true
    end
  end

  if removed then
    return
  end

  -- Guard against tests mutating id/winid directly.
  for popup_id, entry in pairs(popup_by_id) do
    if entry.popup == model then
      popup_by_id[popup_id] = nil
    end
  end
  for wid, entry in pairs(popup_by_winid) do
    if entry.popup == model then
      popup_by_winid[wid] = nil
    end
  end
end

---@param model PeekstackPopupModel
---@param root_winid integer?
local function index_popup(model, root_winid)
  unindex_popup(model)

  local entry = {
    popup = model,
    root_winid = root_winid,
  }
  if model.id ~= nil then
    popup_by_id[model.id] = entry
  end
  if model.winid ~= nil then
    popup_by_winid[model.winid] = entry
  end
end

---@param id integer
---@return PeekstackPopupLookupEntry?
local function lookup_by_id(id)
  local entry = popup_by_id[id]
  if entry and entry.popup and entry.popup.id == id then
    return entry
  end
  popup_by_id[id] = nil

  for root_winid, stack in pairs(stacks) do
    for _, item in ipairs(stack.popups) do
      if item.id == id then
        index_popup(item, root_winid)
        return popup_by_id[id]
      end
    end
  end

  local ephemeral = ephemerals[id]
  if ephemeral then
    index_popup(ephemeral, nil)
    return popup_by_id[id]
  end

  return nil
end

---@param winid integer
---@return PeekstackPopupLookupEntry?
local function lookup_by_winid(winid)
  local entry = popup_by_winid[winid]
  if entry and entry.popup and entry.popup.winid == winid then
    return entry
  end
  popup_by_winid[winid] = nil

  for root_winid, stack in pairs(stacks) do
    for _, item in ipairs(stack.popups) do
      if item.winid == winid then
        index_popup(item, root_winid)
        return popup_by_winid[winid]
      end
    end
  end

  for _, item in pairs(ephemerals) do
    if item.winid == winid then
      index_popup(item, nil)
      return popup_by_winid[winid]
    end
  end

  return nil
end

---@param winid integer
function M._register_stack_view_win(winid)
  stack_view_wins[winid] = true
end

---@param model PeekstackPopupModel
local function register_ephemeral(model)
  ephemerals[model.id] = model
  index_popup(model, nil)
end

---@param id integer
local function unregister_ephemeral(id)
  local model = ephemerals[id]
  if model then
    unindex_popup(model)
  end
  ephemerals[id] = nil
end

---@param id integer
---@return integer?, PeekstackPopupModel?
local function find_ephemeral(id)
  if ephemerals[id] then
    return id, ephemerals[id]
  end
  local entry = lookup_by_winid(id)
  if entry and entry.root_winid == nil then
    return entry.popup.id, entry.popup
  end
  return nil
end

--- Return a non-floating window id. If the given (or current) window is a
--- floating window, walk through the stacks to find its origin window instead.
---@param winid? integer
---@return integer
local function get_root_winid(winid)
  local wid = winid or vim.api.nvim_get_current_win()
  local win_cfg = vim.api.nvim_win_get_config(wid)
  if win_cfg.relative == "" then
    return wid
  end
  local ok_root, root_winid = pcall(vim.api.nvim_win_get_var, wid, "peekstack_root_winid")
  if ok_root and type(root_winid) == "number" and vim.api.nvim_win_is_valid(root_winid) then
    return root_winid
  end
  -- Current window is floating – resolve the owner stack from the popup index.
  local owner = lookup_by_winid(wid)
  if owner and owner.root_winid and vim.api.nvim_win_is_valid(owner.root_winid) then
    return owner.root_winid
  end
  -- Fallback: pick the first non-floating window in the current tabpage.
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(w)
    if cfg.relative == "" then
      return w
    end
  end
  return wid
end

---@param winid? integer
---@return PeekstackStackModel
local function ensure_stack(winid)
  local root_winid = get_root_winid(winid)
  if not stacks[root_winid] then
    stacks[root_winid] = {
      root_winid = root_winid,
      popups = {},
      history = {},
      layout_state = {},
      focused_id = nil,
    }
  end
  return stacks[root_winid]
end

---@param winid? integer
---@return PeekstackStackModel
function M.current_stack(winid)
  return ensure_stack(winid)
end

---@param opts table
---@return integer?
local function resolve_parent_popup_id(opts)
  if opts.parent_popup_id ~= nil then
    return opts.parent_popup_id
  end

  local current_win = vim.api.nvim_get_current_win()
  local owner_stack, current_popup = M.find_by_winid(current_win)
  if owner_stack and current_popup then
    return current_popup.id
  end

  return nil
end

---@param location PeekstackLocation
---@param opts? table
---@return PeekstackPopupModel?
function M.push(location, opts)
  deps()
  opts = opts or {}
  local create_opts = vim.tbl_extend("force", {}, opts)
  create_opts.parent_popup_id = resolve_parent_popup_id(opts)

  -- Handle quick-peek mode (don't add to stack)
  if opts.stack == false then
    local model = popup.create(location, vim.tbl_extend("force", create_opts, { ephemeral = true }))
    if not model then
      return nil
    end
    register_ephemeral(model)

    local data = user_events.build_popup_data(model, vim.api.nvim_get_current_win(), { ephemeral = true })
    user_events.emit("PeekstackPush", data)

    return model
  end

  local stack = ensure_stack()
  local model = popup.create(location, create_opts)
  if not model then
    return nil
  end
  table.insert(stack.popups, model)
  index_popup(model, stack.root_winid)
  stack.focused_id = model.id
  layout.reflow(stack)

  emit_popup_event("PeekstackPush", model, stack.root_winid)

  return model
end

---@param winid? integer
---@return PeekstackPopupModel[]
function M.list(winid)
  local stack = ensure_stack(winid)
  return stack.popups
end

---@param winid? integer
---@return PeekstackPopupModel?
function M.current(winid)
  local stack = ensure_stack(winid)
  return stack.popups[#stack.popups]
end

---@param stack PeekstackStackModel
---@param idx integer
---@param item PeekstackPopupModel
local function close_stack_item(stack, idx, item)
  local current_win = vim.api.nvim_get_current_win()
  local should_restore_focus = item.winid == current_win and vim.w[current_win].peekstack_popup_id ~= nil
  -- Remove from popups BEFORE closing the window to prevent
  -- WinClosed autocmd from re-entering and processing the same popup.
  table.remove(stack.popups, idx)
  unindex_popup(item)

  feedback.highlight_origin(item.origin)
  popup.close(item)

  emit_popup_event("PeekstackClose", item, stack.root_winid)

  -- Save to history for undo close
  history.push_entry(stack, history.build_entry(item, idx))

  user_events.emit("PeekstackHistoryPush", {
    popup_id = item.id,
    location = item.location,
    root_winid = stack.root_winid,
  })

  layout.reflow(stack)

  -- Update focused_id when the focused popup was closed
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

---@param id integer
---@param winid? integer
---@return boolean
function M.close_by_id(id, winid)
  deps()
  local ephemeral_id, ephemeral = find_ephemeral(id)
  if ephemeral_id and ephemeral then
    feedback.highlight_origin(ephemeral.origin)
    popup.close(ephemeral)
    unregister_ephemeral(ephemeral_id)

    user_events.emit(
      "PeekstackClose",
      user_events.build_popup_data(ephemeral, ephemeral.origin and ephemeral.origin.winid or 0)
    )

    return true
  end

  local indexed = lookup_by_id(id)
  if indexed and indexed.root_winid then
    local owner_stack = stacks[indexed.root_winid]
    if owner_stack then
      for idx, item in ipairs(owner_stack.popups) do
        if item.id == id then
          close_stack_item(owner_stack, idx, item)
          return true
        end
      end
    end
  end

  local stack = ensure_stack(winid)
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

  local indexed = lookup_by_winid(id)
  if indexed and indexed.root_winid then
    local owner_stack = stacks[indexed.root_winid]
    if owner_stack then
      for idx, item in ipairs(owner_stack.popups) do
        if item.winid == id then
          close_stack_item(owner_stack, idx, item)
          return true
        end
      end
    end
  end

  local stack = ensure_stack(winid)
  for idx, item in ipairs(stack.popups) do
    if item.winid == id then
      close_stack_item(stack, idx, item)
      return true
    end
  end
  return false
end

---Restore the last closed popup from history (undo close).
---@param winid? integer
---@return PeekstackPopupModel?
function M.restore_last(winid)
  deps()
  return history.restore_last(ensure_stack(winid))
end

---Restore all closed popups from history.
---@param winid? integer
---@return PeekstackPopupModel[]
function M.restore_all(winid)
  deps()
  return history.restore_all(ensure_stack(winid))
end

---Restore a specific history entry by index back into the stack.
---@param idx integer  index in the history list (1-based)
---@param winid? integer
---@return PeekstackPopupModel?
function M.restore_from_history(idx, winid)
  deps()
  return history.restore_from_history(ensure_stack(winid), idx)
end

---Get the history list for a stack.
---@param winid? integer
---@return PeekstackHistoryEntry[]
function M.history_list(winid)
  return ensure_stack(winid).history
end

---Clear the history for a stack.
---@param winid? integer
function M.clear_history(winid)
  deps()
  history.clear(ensure_stack(winid))
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
  local entry = lookup_by_winid(winid)
  if not entry then
    return nil
  end
  if entry.root_winid then
    local stack = stacks[entry.root_winid]
    if stack then
      return stack, entry.popup
    end
  end
  return nil, entry.popup
end

---@param id integer
---@return PeekstackPopupModel?
function M.find_by_id(id)
  local entry = lookup_by_id(id)
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
  local stack = ensure_stack(winid)
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
        emit_popup_event("PeekstackFocus", target, stack.root_winid)
      end
      return ok
    end
  end
  return false
end

---Re-open a popup by id when its window is gone.
---@param id integer
---@param winid? integer
---@return PeekstackPopupModel?
function M.reopen_by_id(id, winid)
  deps()
  local stack = ensure_stack(winid)
  for idx, item in ipairs(stack.popups) do
    if item.id == id then
      local reopen_opts = {
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
      model.id = item.id
      model.pinned = item.pinned or false
      vim.b[model.bufnr].peekstack_popup_id = model.id
      vim.w[model.winid].peekstack_popup_id = model.id
      unindex_popup(item)
      stack.popups[idx] = model
      index_popup(model, stack.root_winid)
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
  local stack = ensure_stack()
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

---@param winid integer
function M.handle_win_closed(winid)
  deps()
  if stack_view_wins[winid] then
    stack_view_wins[winid] = nil
    return
  end
  for id, item in pairs(ephemerals) do
    if item.winid == winid then
      user_events.emit("PeekstackClose", user_events.build_popup_data(item, item.origin and item.origin.winid or 0))
      unregister_ephemeral(id)
    end
  end
  for root_winid, stack in pairs(stacks) do
    if stack.root_winid == winid then
      for idx = #stack.popups, 1, -1 do
        local item = stack.popups[idx]
        emit_popup_event("PeekstackClose", item, root_winid)
        history.push_entry(stack, history.build_entry(item, idx))
        table.remove(stack.popups, idx)
        unindex_popup(item)
        popup.close(item)
      end
      stacks[root_winid] = nil
    else
      local removed = false
      local focused_removed = false
      for idx = #stack.popups, 1, -1 do
        local item = stack.popups[idx]
        if item.winid == winid then
          if stack.focused_id == item.id then
            focused_removed = true
          end
          emit_popup_event("PeekstackClose", item, root_winid)
          feedback.highlight_origin(item.origin)
          table.remove(stack.popups, idx)
          unindex_popup(item)
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

---Rename a popup by id
---@param id integer
---@param title string
---@param winid? integer
---@return boolean
function M.rename_by_id(id, title, winid)
  local stack = ensure_stack(winid)
  for _, item in ipairs(stack.popups) do
    if item.id == id then
      item.title = title
      item.title_chunks = nil
      return true
    end
  end
  return false
end

---Toggle pin state of a popup by id
---@param id integer
---@param winid? integer
---@return boolean
function M.toggle_pin_by_id(id, winid)
  local stack = ensure_stack(winid)
  for _, item in ipairs(stack.popups) do
    if item.id == id then
      item.pinned = not item.pinned
      return true
    end
  end
  return false
end

---@param bufnr integer
function M.handle_buf_wipeout(bufnr)
  deps()
  for id, item in pairs(ephemerals) do
    if item.bufnr == bufnr then
      unregister_ephemeral(id)
    end
  end
  for _, stack in pairs(stacks) do
    for idx = #stack.popups, 1, -1 do
      local item = stack.popups[idx]
      if item.bufnr == bufnr then
        unindex_popup(item)
        table.remove(stack.popups, idx)
      end
    end
    layout.reflow(stack)
  end
end

---Update last_active_at for a popup (when user interacts with it)
---@param winid integer
function M.touch(winid)
  local owner_stack, popup_model = M.find_by_winid(winid)
  if owner_stack and popup_model then
    popup_model.last_active_at = vim.uv.now()
  end
end

---Close stale popups that have exceeded idle_ms
---@param now_ms integer
---@param opts? { idle_ms: integer, ignore_pinned: boolean }
function M.close_stale(now_ms, opts)
  deps()
  opts = opts or {}
  local idle_ms = opts.idle_ms or 300000
  local ignore_pinned = opts.ignore_pinned ~= false
  local prevent_modified = config.get().ui.popup.source.prevent_auto_close_if_modified

  for root_winid, stack in pairs(stacks) do
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

---Handle origin buffer wipeout - close popups whose origin buffer is gone
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
  for id, item in pairs(ephemerals) do
    if should_close_for_origin(item) then
      popup.close(item)
      unregister_ephemeral(id)
    end
  end
  for _root_winid, stack in pairs(stacks) do
    for idx = #stack.popups, 1, -1 do
      local item = stack.popups[idx]
      if should_close_for_origin(item) then
        popup.close(item)
        unindex_popup(item)
        table.remove(stack.popups, idx)
      end
    end
    layout.reflow(stack)
  end
end

---Get all stacks (for cleanup module)
---@return table
function M._all_stacks()
  return stacks
end

---Close all ephemeral popups across stacks and ephemeral registry.
function M.close_ephemerals()
  deps()
  for _, stack in pairs(stacks) do
    local removed = false
    for idx = #stack.popups, 1, -1 do
      local item = stack.popups[idx]
      if item.ephemeral then
        popup.close(item)
        unindex_popup(item)
        table.remove(stack.popups, idx)
        removed = true
      end
    end
    if removed then
      layout.reflow(stack)
    end
  end

  for id, item in pairs(ephemerals) do
    popup.close(item)
    unregister_ephemeral(id)
  end
end

function M.reflow_all()
  deps()
  for _, stack in pairs(stacks) do
    layout.reflow(stack)
  end
end

--- Close all popups in the current (or given) window's stack.
---@param winid? integer
function M.close_all(winid)
  deps()
  local stack = ensure_stack(winid)
  for idx = #stack.popups, 1, -1 do
    local item = stack.popups[idx]
    feedback.highlight_origin(item.origin)
    popup.close(item)

    emit_popup_event("PeekstackClose", item, stack.root_winid)

    history.push_entry(stack, history.build_entry(item, idx))

    unindex_popup(item)
    table.remove(stack.popups, idx)
  end
  stack.focused_id = nil
end

---Get the focused popup id for a stack.
---@param winid? integer
---@return integer?
function M.focused_id(winid)
  local stack = ensure_stack(winid)
  return stack.focused_id
end

--- Reset all stacks (for testing).
function M._reset()
  stacks = {}
  ephemerals = {}
  stack_view_wins = {}
  popup_by_id = {}
  popup_by_winid = {}
end

---Get ephemeral popups (for testing).
---@return table<integer, PeekstackPopupModel>
function M._ephemerals()
  return ephemerals
end

return M
