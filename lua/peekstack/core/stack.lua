local state = require("peekstack.core.stack.state")
local operations = require("peekstack.core.stack.operations")
local events = require("peekstack.core.stack.events")

local M = {}

M._register_stack_view_win = state.register_stack_view_win
M.current_stack = state.ensure_stack

M.push = operations.push
M.reflow = operations.reflow
M.list = operations.list
M.current = operations.current
M.close_by_id = operations.close_by_id
M.close = operations.close
M.restore_last = operations.restore_last
M.restore_all = operations.restore_all
M.restore_from_history = operations.restore_from_history
M.history_list = operations.history_list
M.clear_history = operations.clear_history
M.close_current = operations.close_current
M.find_by_winid = operations.find_by_winid
M.find_by_id = operations.find_by_id
M.focus_by_id = operations.focus_by_id
M.reopen_by_id = operations.reopen_by_id
M.focus_next = operations.focus_next
M.focus_prev = operations.focus_prev
M.rename_by_id = operations.rename_by_id
M.toggle_pin_by_id = operations.toggle_pin_by_id
M.touch = operations.touch
M.close_stale = operations.close_stale
M.close_ephemerals = operations.close_ephemerals
M.reflow_all = operations.reflow_all
M.toggle = operations.toggle
M.is_hidden = operations.is_hidden
M.toggle_zoom = operations.toggle_zoom
M.is_zoomed = operations.is_zoomed
M.close_all = operations.close_all
M.focused_id = operations.focused_id

M.handle_win_closed = events.handle_win_closed
M.handle_buf_wipeout = events.handle_buf_wipeout
M.handle_origin_wipeout = events.handle_origin_wipeout

---@return table<integer, PeekstackStackModel>
function M._all_stacks()
  return state.stacks
end

---@param winid? integer
---@return integer
function M.get_root_winid(winid)
  return state.get_root_winid(winid)
end

function M._reset()
  state.reset()
end

---@return table<integer, PeekstackPopupModel>
function M._ephemerals()
  return state.ephemerals
end

return M
