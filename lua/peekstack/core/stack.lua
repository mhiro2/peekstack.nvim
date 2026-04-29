local state = require("peekstack.core.stack.state")
local events = require("peekstack.core.stack.events")
local push_ops = require("peekstack.core.stack.operations.push")
local close_ops = require("peekstack.core.stack.operations.close")
local focus_ops = require("peekstack.core.stack.operations.focus")
local history_ops = require("peekstack.core.stack.operations.history")
local visibility_ops = require("peekstack.core.stack.operations.visibility")
local cleanup_ops = require("peekstack.core.stack.operations.cleanup")
local query_ops = require("peekstack.core.stack.operations.query")

local M = {}

M._register_stack_view_win = state.register_stack_view_win
M.current_stack = state.ensure_stack

M.push = push_ops.push

M.close = close_ops.close
M.close_by_id = close_ops.close_by_id
M.close_current = close_ops.close_current
M.close_all = close_ops.close_all

M.focus_by_id = focus_ops.focus_by_id
M.focus_next = focus_ops.focus_next
M.focus_prev = focus_ops.focus_prev
M.reopen_by_id = focus_ops.reopen_by_id

M.restore_last = history_ops.restore_last
M.restore_all = history_ops.restore_all
M.restore_from_history = history_ops.restore_from_history
M.history_list = history_ops.history_list
M.clear_history = history_ops.clear_history

M.reflow = visibility_ops.reflow
M.reflow_all = visibility_ops.reflow_all
M.toggle = visibility_ops.toggle
M.is_hidden = visibility_ops.is_hidden
M.toggle_zoom = visibility_ops.toggle_zoom
M.is_zoomed = visibility_ops.is_zoomed

M.close_stale = cleanup_ops.close_stale
M.close_ephemerals = cleanup_ops.close_ephemerals

M.list = query_ops.list
M.current = query_ops.current
M.focused_id = query_ops.focused_id
M.find_by_winid = query_ops.find_by_winid
M.find_by_id = query_ops.find_by_id
M.touch = query_ops.touch
M.rename_by_id = query_ops.rename_by_id
M.toggle_pin_by_id = query_ops.toggle_pin_by_id

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
