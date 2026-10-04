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

---@param winid any
---@return boolean
local function is_live_win(winid)
  return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

---Popup windows are editor-relative, so they always open in the current
---tabpage. Owning them from a stack rooted in another tabpage would split
---display and ownership.
---@param winid integer
---@return boolean
local function is_current_tabpage_win(winid)
  local ok, tabpage = pcall(vim.api.nvim_win_get_tabpage, winid)
  return ok and tabpage == vim.api.nvim_get_current_tabpage()
end

---@class PeekstackPushTarget
---@field origin_winid integer
---@field root_winid integer
---@field infer_parent boolean

---Resolve where the popup belongs. Async providers and pickers may complete
---after the user moved away, so callers freeze the requesting window through
---opts.origin_winid/opts.root_winid. Once frozen, the current window is never
---consulted again: if the frozen windows are gone the request is dropped
---rather than redirected to whatever window happens to be focused now.
---@param opts table
---@return PeekstackPushTarget?
local function resolve_target(opts)
  if opts.origin_winid == nil and opts.root_winid == nil then
    local current = vim.api.nvim_get_current_win()
    return { origin_winid = current, root_winid = current, infer_parent = true }
  end

  if is_live_win(opts.origin_winid) then
    return {
      origin_winid = opts.origin_winid,
      root_winid = is_live_win(opts.root_winid) and opts.root_winid or opts.origin_winid,
      infer_parent = true,
    }
  end

  -- The requesting window is gone; keep the frozen root and drop the parent
  -- relation, which belonged to the closed window.
  if is_live_win(opts.root_winid) then
    return { origin_winid = opts.root_winid, root_winid = opts.root_winid, infer_parent = false }
  end

  return nil
end

---@param opts table
---@param target PeekstackPushTarget
---@return integer?
local function resolve_parent_popup_id(opts, target)
  if opts.parent_popup_id ~= nil then
    return opts.parent_popup_id
  end
  if not target.infer_parent then
    return nil
  end

  local owner = state.lookup_by_winid(target.origin_winid)
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
  local target = resolve_target(opts)
  if not target or not is_current_tabpage_win(target.root_winid) then
    return nil
  end

  local root_winid = state.get_root_winid(target.root_winid)
  local create_opts = vim.tbl_extend("force", {}, opts)
  create_opts.defer_reflow = nil
  create_opts.root_winid = nil
  create_opts.origin_winid = target.origin_winid
  create_opts.parent_popup_id = resolve_parent_popup_id(opts, target)

  if opts.stack == false then
    local model = popup.create(location, vim.tbl_extend("force", create_opts, { ephemeral = true }))
    if not model then
      return nil
    end
    state.register_ephemeral(model, root_winid)

    local data = user_events.build_popup_data(model, root_winid, { ephemeral = true })
    user_events.emit("PeekstackPush", data)

    return model
  end

  local stack = state.ensure_stack(root_winid)
  require("peekstack.core.stack.operations.visibility").show(stack)
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
