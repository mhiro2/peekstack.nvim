local state = require("peekstack.core.stack.state")
local common = require("peekstack.core.stack.common")

local M = {}

local config
local function deps()
  if not config then
    config = require("peekstack.config")
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

  -- Collect first: closing one popup can wipe buffers whose handlers close
  -- others while this loop runs.
  local stale = {}
  for root_winid, stack in pairs(state.stacks) do
    for idx = #stack.popups, 1, -1 do
      local item = stack.popups[idx]
      if (not ignore_pinned or not item.pinned) and item.last_active_at then
        local is_modified_source = prevent_modified
          and item.buffer_mode == "source"
          and vim.api.nvim_buf_is_valid(item.bufnr)
          and vim.bo[item.bufnr].modified

        if not is_modified_source and now_ms - item.last_active_at > idle_ms then
          table.insert(stale, { id = item.id, root_winid = root_winid })
        end
      end
    end
  end

  local close = require("peekstack.core.stack.operations.close")
  for _, target in ipairs(stale) do
    if state.lookup_by_id(target.id) then
      close.close_by_id(target.id, target.root_winid)
    end
  end
end

---@param winid? integer
function M.close_ephemerals(winid)
  local target_root_winid = state.get_root_winid(winid)
  for id, item in pairs(state.ephemerals) do
    if state.ephemeral_root_winid(item) == target_root_winid then
      common.remove_ephemeral(id, item)
    end
  end
end

return M
