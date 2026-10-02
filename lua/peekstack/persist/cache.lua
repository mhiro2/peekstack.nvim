local M = {}

---Sessions keyed by the store file they were read from, so a cached snapshot
---of one repository is never served for another after a directory change.
---@type table<string, table<string, PeekstackSession>>
local cached_sessions = {}

---@param path string
---@param data PeekstackStoreData
---@return PeekstackStoreData
function M.update(path, data)
  cached_sessions[path] = data.sessions or {}
  return data
end

---@param path string
---@return table<string, PeekstackSession>
function M.get(path)
  return cached_sessions[path] or {}
end

---@param path string
---@return boolean
function M.is_loaded(path)
  return cached_sessions[path] ~= nil
end

function M.reset()
  cached_sessions = {}
end

return M
