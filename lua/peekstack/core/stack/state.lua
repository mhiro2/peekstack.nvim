local M = {}

---@class PeekstackPopupLookupEntry
---@field popup PeekstackPopupModel
---@field root_winid integer?

---@type table<integer, PeekstackStackModel>
M.stacks = {}
---@type table<integer, PeekstackPopupModel>
M.ephemerals = {}
---@type table<integer, boolean>
M.stack_view_wins = {}
---@type table<integer, PeekstackPopupLookupEntry>
M.popup_by_id = {}
---@type table<integer, PeekstackPopupLookupEntry>
M.popup_by_winid = {}
---@type boolean
M.suppress_win_events = false

---@param winid? integer
---@return integer
local get_root_winid

---@param model PeekstackPopupModel
---@return integer?
local function resolve_ephemeral_root_winid(model)
  if not model or not model.origin then
    return nil
  end
  local origin_winid = model.origin.winid
  if type(origin_winid) ~= "number" or not vim.api.nvim_win_is_valid(origin_winid) then
    return nil
  end
  local ok_root, root_winid = pcall(get_root_winid, origin_winid)
  if ok_root and type(root_winid) == "number" and vim.api.nvim_win_is_valid(root_winid) then
    return root_winid
  end
  return nil
end

---@param model PeekstackPopupModel
function M.unindex_popup(model)
  if not model then
    return
  end

  local removed = false

  local id = model.id
  if id ~= nil then
    local entry_by_id = M.popup_by_id[id]
    if entry_by_id and entry_by_id.popup == model then
      M.popup_by_id[id] = nil
      removed = true
    end
  end

  local winid = model.winid
  if winid ~= nil then
    local entry_by_winid = M.popup_by_winid[winid]
    if entry_by_winid and entry_by_winid.popup == model then
      M.popup_by_winid[winid] = nil
      removed = true
    end
  end

  if removed then
    return
  end

  -- Guard against tests mutating id/winid directly.
  for popup_id, entry in pairs(M.popup_by_id) do
    if entry.popup == model then
      M.popup_by_id[popup_id] = nil
    end
  end
  for wid, entry in pairs(M.popup_by_winid) do
    if entry.popup == model then
      M.popup_by_winid[wid] = nil
    end
  end
end

---@param model PeekstackPopupModel
---@param root_winid integer?
function M.index_popup(model, root_winid)
  M.unindex_popup(model)

  local entry = {
    popup = model,
    root_winid = root_winid,
  }
  if model.id ~= nil then
    M.popup_by_id[model.id] = entry
  end
  if model.winid ~= nil then
    M.popup_by_winid[model.winid] = entry
  end
end

---@param id integer
---@return PeekstackPopupLookupEntry?
function M.lookup_by_id(id)
  local entry = M.popup_by_id[id]
  if entry and entry.popup and entry.popup.id == id then
    return entry
  end
  M.popup_by_id[id] = nil

  for root_winid, stack in pairs(M.stacks) do
    for _, item in ipairs(stack.popups) do
      if item.id == id then
        M.index_popup(item, root_winid)
        return M.popup_by_id[id]
      end
    end
  end

  local ephemeral = M.ephemerals[id]
  if ephemeral then
    M.index_popup(ephemeral, nil)
    return M.popup_by_id[id]
  end

  return nil
end

---@param winid integer
---@return PeekstackPopupLookupEntry?
function M.lookup_by_winid(winid)
  local entry = M.popup_by_winid[winid]
  if entry and entry.popup and entry.popup.winid == winid then
    return entry
  end
  M.popup_by_winid[winid] = nil

  for root_winid, stack in pairs(M.stacks) do
    for _, item in ipairs(stack.popups) do
      if item.winid == winid then
        M.index_popup(item, root_winid)
        return M.popup_by_winid[winid]
      end
    end
  end

  for _, item in pairs(M.ephemerals) do
    if item.winid == winid then
      M.index_popup(item, resolve_ephemeral_root_winid(item))
      return M.popup_by_winid[winid]
    end
  end

  return nil
end

---@param winid integer
function M.register_stack_view_win(winid)
  M.stack_view_wins[winid] = true
end

---@param model PeekstackPopupModel
function M.register_ephemeral(model)
  M.ephemerals[model.id] = model
  M.index_popup(model, resolve_ephemeral_root_winid(model))
end

---@param id integer
function M.unregister_ephemeral(id)
  local model = M.ephemerals[id]
  if model then
    M.unindex_popup(model)
  end
  M.ephemerals[id] = nil
end

---@param id integer
---@return integer?, PeekstackPopupModel?
function M.find_ephemeral(id)
  if M.ephemerals[id] then
    return id, M.ephemerals[id]
  end
  local entry = M.lookup_by_winid(id)
  if entry and entry.popup and entry.popup.ephemeral then
    return entry.popup.id, entry.popup
  end
  return nil
end

--- Return a non-floating window id. If the given (or current) window is a
--- floating window, walk through the stacks to find its origin window instead.
---@param winid? integer
---@return integer
get_root_winid = function(winid)
  local wid = winid or vim.api.nvim_get_current_win()
  local win_cfg = vim.api.nvim_win_get_config(wid)
  if win_cfg.relative == "" then
    return wid
  end
  local ok_root, root_winid = pcall(vim.api.nvim_win_get_var, wid, "peekstack_root_winid")
  if ok_root and type(root_winid) == "number" and vim.api.nvim_win_is_valid(root_winid) then
    return root_winid
  end
  -- Current window is floating; resolve the owner stack from the popup index.
  local owner = M.lookup_by_winid(wid)
  if owner and owner.root_winid and vim.api.nvim_win_is_valid(owner.root_winid) then
    return owner.root_winid
  end
  -- Fallback: pick the first non-floating window in the current tabpage.
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(w)
    if cfg.relative == "" then
      return w
    end
  end
  return wid
end

---@param winid? integer
---@return integer
function M.get_root_winid(winid)
  return get_root_winid(winid)
end

---@param winid? integer
---@return PeekstackStackModel
function M.ensure_stack(winid)
  local root_winid = get_root_winid(winid)
  if not M.stacks[root_winid] then
    M.stacks[root_winid] = {
      root_winid = root_winid,
      popups = {},
      history = {},
      layout_state = {},
      focused_id = nil,
    }
  end
  return M.stacks[root_winid]
end

function M.reset()
  M.stacks = {}
  M.ephemerals = {}
  M.stack_view_wins = {}
  M.popup_by_id = {}
  M.popup_by_winid = {}
  M.suppress_win_events = false
end

return M
