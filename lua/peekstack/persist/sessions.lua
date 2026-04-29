local config = require("peekstack.config")
local stack = require("peekstack.core.stack")

local M = {}

---Resolve the session name to use, falling back to the configured default.
---@param name? string
---@return string
function M.resolve_name(name)
  if name and name ~= "" then
    return name
  end

  local cfg = config.get()
  if cfg.persist.session and cfg.persist.session.default_name then
    return cfg.persist.session.default_name
  end

  return "default"
end

---Resolve the root window id to use when collecting stack items.
---@param root_winid? integer
---@return integer
function M.resolve_root_winid(root_winid)
  if root_winid and type(root_winid) == "number" and vim.api.nvim_win_is_valid(root_winid) then
    return root_winid
  end

  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)
  if vim.bo[bufnr].filetype == "peekstack-stack" then
    local ok, stack_root_winid = pcall(vim.api.nvim_win_get_var, winid, "peekstack_root_winid")
    if ok and type(stack_root_winid) == "number" and vim.api.nvim_win_is_valid(stack_root_winid) then
      return stack_root_winid
    end
  end

  return winid
end

---Collect the current stack items (truncated to `persist.max_items`).
---@param root_winid? integer
---@return PeekstackSessionItem[]
function M.collect_items(root_winid)
  local data_items = {}
  for _, popup in ipairs(stack.list(M.resolve_root_winid(root_winid))) do
    data_items[#data_items + 1] = {
      uri = popup.location.uri,
      range = popup.location.range,
      title = popup.title,
      provider = popup.location.provider,
      ts = os.time(),
      popup_id = popup.id,
      pinned = popup.pinned or nil,
      buffer_mode = popup.buffer_mode ~= "copy" and popup.buffer_mode or nil,
      parent_popup_id = popup.parent_popup_id,
    }
  end

  local max_items = config.get().persist.max_items or 200
  if #data_items > max_items then
    data_items = vim.list_slice(data_items, #data_items - max_items + 1, #data_items)
  end

  return data_items
end

---Insert or update a session in the given store data.
---@param data PeekstackStoreData
---@param name string
---@param items PeekstackSessionItem[]
---@return PeekstackStoreData
function M.upsert(data, name, items)
  local now = os.time()
  if data.sessions[name] then
    data.sessions[name].items = items
    data.sessions[name].meta.updated_at = now
  else
    data.sessions[name] = {
      items = items,
      meta = {
        created_at = now,
        updated_at = now,
      },
    }
  end
  return data
end

---Delete a session from the given store data.
---@param data PeekstackStoreData
---@param name string
---@return boolean ok true if the session existed and was removed
function M.delete(data, name)
  if not data.sessions[name] then
    return false
  end
  data.sessions[name] = nil
  return true
end

---@class PeekstackSessionsRenameResult
---@field ok boolean
---@field err? "missing"|"exists"

---Rename a session in the given store data.
---@param data PeekstackStoreData
---@param from string
---@param to string
---@return PeekstackSessionsRenameResult
function M.rename(data, from, to)
  if not data.sessions[from] then
    return { ok = false, err = "missing" }
  end
  if data.sessions[to] then
    return { ok = false, err = "exists" }
  end

  data.sessions[to] = data.sessions[from]
  data.sessions[from] = nil
  data.sessions[to].meta.updated_at = os.time()
  return { ok = true }
end

return M
