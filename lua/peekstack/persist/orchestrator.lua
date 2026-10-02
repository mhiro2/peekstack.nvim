local config = require("peekstack.config")
local fs = require("peekstack.util.fs")
local cache = require("peekstack.persist.cache")
local migrate = require("peekstack.persist.migrate")
local store = require("peekstack.persist.store")
local notify = require("peekstack.util.notify")

local M = {}

local SCOPE = "repo"

---Resolve the store file for the current working directory.
---Every operation resolves it once when it is accepted and carries it through
---its read, write and cache update, so a `:cd` while the operation is in
---flight cannot redirect it to another repository's store.
---@return string
function M.store_path()
  return fs.scope_path(SCOPE)
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
---@param path string
---@param on_done fun(data: PeekstackStoreData)
function M.read_async(path, on_done)
  store.read(path, {
    on_done = function(read_data)
      on_done(M.ensure_data(read_data))
    end,
  })
end

---Synchronously read and migrate store data without touching the cache.
---@param path string
---@return PeekstackStoreData
function M.read_sync(path)
  return M.ensure_data(store.read_sync(path))
end

---Asynchronously read store data and refresh the cache from disk.
---Used by read-only flows (restore, list_sessions) that should reflect the
---latest persisted state in memory.
---@param path string
---@param on_done fun(data: PeekstackStoreData)
function M.refresh_cache_async(path, on_done)
  M.read_async(path, function(data)
    cache.update(path, data)
    on_done(data)
  end)
end

---Synchronously read store data and refresh the cache from disk.
---@param path string
---@return PeekstackStoreData
function M.refresh_cache_sync(path)
  local data = M.read_sync(path)
  cache.update(path, data)
  return data
end

---Asynchronously write data; on success refresh cache before calling `on_done`.
---@param path string
---@param data PeekstackStoreData
---@param on_done? fun(success: boolean)
function M.write_async(path, data, on_done)
  store.write(path, data, {
    on_done = function(success)
      if success then
        cache.update(path, data)
      end
      if on_done then
        on_done(success)
      end
    end,
  })
end

---Synchronously write data; on success refresh cache.
---@param path string
---@param data PeekstackStoreData
---@return boolean
function M.write_sync(path, data)
  local success = store.write_sync(path, data)
  if success then
    cache.update(path, data)
  end
  return success
end

---@class PeekstackPersistUpdate
---@field path string
---@field mutate fun(data: PeekstackStoreData): boolean
---@field on_done? fun(success: boolean)

---@type PeekstackPersistUpdate[]
local update_queue = {}
local update_running = false

local function run_next_update()
  local update = table.remove(update_queue, 1)
  if not update then
    update_running = false
    return
  end
  update_running = true

  local function finish(success)
    if update.on_done then
      -- A throwing callback must not wedge the queue with update_running=true.
      local ok, err = pcall(update.on_done, success)
      if not ok then
        notify.warn("Session update callback failed: " .. tostring(err))
      end
    end
    run_next_update()
  end

  M.read_async(update.path, function(data)
    local ok, keep = pcall(update.mutate, data)
    if not ok then
      notify.warn("Failed to update session data: " .. tostring(keep))
      finish(false)
      return
    end
    if not keep then
      finish(false)
      return
    end
    M.write_async(update.path, data, finish)
  end)
end

---Asynchronously read, mutate and write back store data at `path`.
---Updates are serialized: each one reads the file only after the previous
---write finished, so overlapping save/delete/rename calls cannot clobber each
---other with a stale snapshot (read-modify-write lost update).
---`mutate` returns true to persist the change or false to abort without
---writing; `on_done` receives whether the data was written successfully.
---@param path string
---@param mutate fun(data: PeekstackStoreData): boolean
---@param on_done? fun(success: boolean)
function M.update_async(path, mutate, on_done)
  update_queue[#update_queue + 1] = { path = path, mutate = mutate, on_done = on_done }
  if not update_running then
    run_next_update()
  end
end

---Upper bound for draining in-flight async updates before a sync update.
local UPDATE_SYNC_DRAIN_MS = 1000

---Synchronously read, mutate and write back store data at `path`.
---Drains queued async updates first (bounded by UPDATE_SYNC_DRAIN_MS) so a
---sync save issued while an async save is mid-flight does not race it; the
---sync write itself then runs atomically from Lua's point of view.
---@param path string
---@param mutate fun(data: PeekstackStoreData): boolean
---@return boolean success whether the data was written
function M.update_sync(path, mutate)
  if update_running then
    vim.wait(UPDATE_SYNC_DRAIN_MS, function()
      return not update_running
    end, 10)
  end

  local data = M.read_sync(path)
  if not mutate(data) then
    return false
  end
  return M.write_sync(path, data)
end

---Reset the in-memory session cache and drop queued updates.
function M.reset_cache()
  cache.reset()
  update_queue = {}
  update_running = false
end

---@param path string
---@return boolean
function M.cache_loaded(path)
  return cache.is_loaded(path)
end

---@param path string
---@return table<string, PeekstackSession>
function M.cache_sessions(path)
  return cache.get(path)
end

return M
