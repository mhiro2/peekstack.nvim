local state = require("peekstack.core.stack.state")

local M = {}

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

---@param winid? integer
---@return integer?
function M.focused_id(winid)
  return state.ensure_stack(winid).focused_id
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

---@param winid integer
function M.touch(winid)
  local owner_stack, popup_model = M.find_by_winid(winid)
  if owner_stack and popup_model then
    popup_model.last_active_at = vim.uv.now()
  end
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

return M
