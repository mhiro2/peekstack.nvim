local config = require("peekstack.config")
local cache = require("peekstack.persist.cache")
local migrate = require("peekstack.persist.migrate")
local store = require("peekstack.persist.store")
local notify = require("peekstack.util.notify")

local M = {}

local SCOPE = "repo"

---@return string
function M.scope()
  return SCOPE
end

---@param data PeekstackStoreData
---@return PeekstackStoreData
function M.ensure_data(data)
  return migrate.ensure(data)
end

---Check if persistence is enabled, optionally notifying when disabled.
---@param silent? boolean
---@return boolean
function M.ensure_enabled(silent)
  if not config.get().persist.enabled then
    if not silent then
      notify.info("peekstack.persist is disabled")
    end
    return false
  end
  return true
end

---Asynchronously read store data and pass migrated data to `on_done`.
---Does NOT touch the cache; callers that want to refresh it should use
---`refresh_cache_async` instead. This keeps save/delete/rename flows from
---updating the cache before a successful write.
---@param on_done fun(data: PeekstackStoreData)
function M.read_async(on_done)
  store.read(SCOPE, {
    on_done = function(read_data)
      on_done(M.ensure_data(read_data))
    end,
  })
end

---Synchronously read and migrate store data without touching the cache.
---@return PeekstackStoreData
function M.read_sync()
  return M.ensure_data(store.read_sync(SCOPE))
end

---Asynchronously read store data and refresh the cache from disk.
---Used by read-only flows (restore, list_sessions) that should reflect the
---latest persisted state in memory.
---@param on_done fun(data: PeekstackStoreData)
function M.refresh_cache_async(on_done)
  M.read_async(function(data)
    cache.update(data)
    on_done(data)
  end)
end

---Synchronously read store data and refresh the cache from disk.
---@return PeekstackStoreData
function M.refresh_cache_sync()
  local data = M.read_sync()
  cache.update(data)
  return data
end

---Asynchronously write data; on success refresh cache before calling `on_done`.
---@param data PeekstackStoreData
---@param on_done? fun(success: boolean)
function M.write_async(data, on_done)
  store.write(SCOPE, data, {
    on_done = function(success)
      if success then
        cache.update(data)
      end
      if on_done then
        on_done(success)
      end
    end,
  })
end

---Synchronously write data; on success refresh cache.
---@param data PeekstackStoreData
---@return boolean
function M.write_sync(data)
  local success = store.write_sync(SCOPE, data)
  if success then
    cache.update(data)
  end
  return success
end

---Reset the in-memory session cache.
function M.reset_cache()
  cache.reset()
end

---@return boolean
function M.cache_loaded()
  return cache.is_loaded()
end

---@return table<string, PeekstackSession>
function M.cache_sessions()
  return cache.get()
end

return M
