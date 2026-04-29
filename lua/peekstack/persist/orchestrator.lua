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

---Migrate read data and refresh the in-memory cache.
---@param read_data PeekstackStoreData
---@return PeekstackStoreData
function M.update_cache(read_data)
  return cache.update(M.ensure_data(read_data))
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

---Asynchronously read store data, refresh cache, and pass migrated data to `on_done`.
---@param on_done fun(data: PeekstackStoreData)
function M.read_async(on_done)
  store.read(SCOPE, {
    on_done = function(read_data)
      on_done(M.update_cache(read_data))
    end,
  })
end

---Synchronously read store data and refresh cache.
---@return PeekstackStoreData
function M.read_sync()
  return M.update_cache(store.read_sync(SCOPE))
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
