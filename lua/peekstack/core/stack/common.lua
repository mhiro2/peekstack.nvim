local M = {}

local popup, user_events
local function deps()
  if not popup then
    popup = require("peekstack.core.popup")
    user_events = require("peekstack.core.user_events")
  end
end

---@param event string
---@param popup_model PeekstackPopupModel
---@param root_winid integer
function M.emit_popup_event(event, popup_model, root_winid)
  deps()
  user_events.emit(event, user_events.build_popup_data(popup_model, root_winid))
end

---Re-create a popup window for an existing stack item.
---@param item PeekstackPopupModel
---@param stack PeekstackStackModel
---@return PeekstackPopupModel?
function M.reopen_popup(item, stack)
  deps()
  local reopen_opts = {
    id = item.id,
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
  model.pinned = item.pinned or false
  return model
end

return M
