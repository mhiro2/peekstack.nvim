local state = require("peekstack.core.stack.state")

local M = {}

local config, layout, popup, user_events
local function deps()
  if not config then
    config = require("peekstack.config")
    layout = require("peekstack.core.layout")
    popup = require("peekstack.core.popup")
    user_events = require("peekstack.core.user_events")
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

  local close = require("peekstack.core.stack.operations.close")
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
            close.close(item.id, root_winid)
          end
        end
      end
    end
  end
end

---@param winid? integer
function M.close_ephemerals(winid)
  deps()
  local target_root_winid = nil
  if winid ~= nil or vim.api.nvim_get_current_win() ~= nil then
    target_root_winid = state.get_root_winid(winid)
  end

  for _, stack in pairs(state.stacks) do
    if target_root_winid == nil or stack.root_winid == target_root_winid then
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
  end

  for id, item in pairs(state.ephemerals) do
    local entry = state.lookup_by_id(item.id)
    local root_winid = entry and entry.root_winid or nil
    if target_root_winid == nil or root_winid == target_root_winid then
      popup.close(item)
      state.unregister_ephemeral(id)
      user_events.emit(
        "PeekstackClose",
        user_events.build_popup_data(item, item.origin and item.origin.winid or 0, { ephemeral = true })
      )
    end
  end
end

return M
