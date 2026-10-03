local state = require("peekstack.core.stack.state")
local common = require("peekstack.core.stack.common")

local M = {}

---Remove every stack and ephemeral popup matching `predicate`.
---@param predicate fun(item: PeekstackPopupModel): boolean
local function remove_matching(predicate)
  -- Collect first: a removal can wipe buffers and re-enter this module.
  local ephemerals = {}
  for id, item in pairs(state.ephemerals) do
    if predicate(item) then
      ephemerals[id] = item
    end
  end
  for id, item in pairs(ephemerals) do
    if state.ephemerals[id] == item then
      common.remove_ephemeral(id, item)
    end
  end
  for _, stack in pairs(vim.tbl_values(state.stacks)) do
    if common.remove_stack_popups(stack, predicate) then
      common.settle(stack)
    end
  end
end

---@param winid integer
function M.handle_win_closed(winid)
  if state.suppress_win_events then
    return
  end
  if state.stack_view_wins[winid] then
    state.stack_view_wins[winid] = nil
    return
  end
  local root_stack = state.stacks[winid]
  if root_stack then
    -- Drop the stack before closing its popups so their WinClosed events
    -- do not find it again.
    state.stacks[winid] = nil
    common.remove_stack_popups(root_stack, function()
      return true
    end, { highlight_origin = false })
  end
  remove_matching(function(item)
    return item.winid == winid
  end)
end

---@param bufnr integer
function M.handle_buf_wipeout(bufnr)
  if state.suppress_win_events then
    return
  end
  remove_matching(function(item)
    if item.bufnr ~= bufnr then
      return false
    end
    -- A buffer wiped while its popup window still shows it is being replaced
    -- in that window (`:buffer`, `:edit`); handle_buf_win_enter makes the
    -- popup follow the new buffer instead.
    local winid = item.winid
    return not (winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr)
  end)
end

---Follow a buffer that replaced the one shown in a popup window.
---@param winid integer
---@param bufnr integer
function M.handle_buf_win_enter(winid, bufnr)
  local entry = state.lookup_by_winid(winid)
  if not entry or entry.popup.bufnr == bufnr then
    return
  end
  require("peekstack.core.popup").retarget(entry.popup, bufnr)
  require("peekstack.ui.stack_view").refresh_all()
end

---@param bufnr integer
function M.handle_origin_wipeout(bufnr)
  remove_matching(function(item)
    return common.closes_with_origin(item) and item.origin.bufnr == bufnr
  end)
end

return M
