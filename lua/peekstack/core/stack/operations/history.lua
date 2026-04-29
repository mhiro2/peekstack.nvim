local state = require("peekstack.core.stack.state")

local M = {}

local history_core
local function deps()
  if not history_core then
    history_core = require("peekstack.core.history")
  end
end

---@param winid? integer
---@return PeekstackPopupModel?
function M.restore_last(winid)
  deps()
  return history_core.restore_last(state.ensure_stack(winid))
end

---@param winid? integer
---@return PeekstackPopupModel[]
function M.restore_all(winid)
  deps()
  return history_core.restore_all(state.ensure_stack(winid))
end

---@param idx integer
---@param winid? integer
---@return PeekstackPopupModel?
function M.restore_from_history(idx, winid)
  deps()
  return history_core.restore_from_history(state.ensure_stack(winid), idx)
end

---@param winid? integer
---@return PeekstackHistoryEntry[]
function M.history_list(winid)
  return state.ensure_stack(winid).history
end

---@param winid? integer
function M.clear_history(winid)
  deps()
  history_core.clear(state.ensure_stack(winid))
end

return M
