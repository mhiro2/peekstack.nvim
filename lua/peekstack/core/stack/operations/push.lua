local state = require("peekstack.core.stack.state")
local common = require("peekstack.core.stack.common")

local M = {}

local layout, popup, user_events
local function deps()
  if not layout then
    layout = require("peekstack.core.layout")
    popup = require("peekstack.core.popup")
    user_events = require("peekstack.core.user_events")
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
    require("peekstack.core.stack.operations.visibility").toggle(stack.root_winid)
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

return M
