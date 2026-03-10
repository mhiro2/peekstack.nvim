local M = {}

---@type table<string, PeekstackSession>
local cached_sessions = {}
local cache_loaded = false

---@param data PeekstackStoreData
---@return PeekstackStoreData
function M.update(data)
  cached_sessions = data.sessions or {}
  cache_loaded = true
  return data
end

---@return table<string, PeekstackSession>
function M.get()
  return cached_sessions
end

---@return boolean
function M.is_loaded()
  return cache_loaded
end

function M.reset()
  cached_sessions = {}
  cache_loaded = false
end

return M
