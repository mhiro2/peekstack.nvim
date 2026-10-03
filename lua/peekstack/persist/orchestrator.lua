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

---Migrate data read from `path`. Unsupported versions (e.g. a store written
---by a newer release) yield nil so that the file is left untouched.
---@param path string
---@param data PeekstackStoreData?
---@return PeekstackStoreData?
local function ensure_data(path, data)
  if not data then
    return nil
  end
  if not migrate.supports(data.version) then
    notify.warn(string.format("Unsupported session data version %s: %s", tostring(data.version), path))
    return nil
  end
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
---`data` is nil when the store could not be read or decoded; callers must
---then leave the file alone instead of treating it as empty.
---Does NOT touch the cache; callers that want to refresh it should use
---`refresh_cache_async` instead. This keeps save/delete/rename flows from
---updating the cache before a successful write.
---@param path string
---@param on_done fun(data: PeekstackStoreData?)
function M.read_async(path, on_done)
  store.read(path, {
    on_done = function(read_data)
      on_done(ensure_data(path, read_data))
    end,
  })
end

---Synchronously read and migrate store data without touching the cache.
---@param path string
---@return PeekstackStoreData? data nil when the store could not be read
function M.read_sync(path)
  return ensure_data(path, store.read_sync(path))
end

---Asynchronously read store data and refresh the cache from disk.
---Used by read-only flows (restore, list_sessions) that should reflect the
---latest persisted state in memory. A failed read keeps the cache as is.
---@param path string
---@param on_done fun(data: PeekstackStoreData?)
function M.refresh_cache_async(path, on_done)
  M.read_async(path, function(data)
    if data then
      cache.update(path, data)
    end
    on_done(data)
  end)
end

---Synchronously read store data and refresh the cache from disk.
---@param path string
---@return PeekstackStoreData? data nil when the store could not be read
function M.refresh_cache_sync(path)
  local data = M.read_sync(path)
  if data then
    cache.update(path, data)
  end
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
---@field sync? boolean read and write with blocking I/O when its turn comes

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
    -- Release the queue before the callback so an update it enqueues (e.g. a
    -- sync save from a PeekstackSave handler) can run instead of waiting on
    -- this finished one. Earlier queued updates still go first.
    update_running = false
    if update.on_done then
      -- A throwing callback must not stop the queue.
      local ok, err = pcall(update.on_done, success)
      if not ok then
        notify.warn("Session update callback failed: " .. tostring(err))
      end
    end
    if not update_running then
      run_next_update()
    end
  end

  ---@param data PeekstackStoreData?
  local function apply(data)
    if not data then
      -- Never write over a store that could not be read.
      finish(false)
      return
    end
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
    if update.sync then
      finish(M.write_sync(update.path, data))
    else
      M.write_async(update.path, data, finish)
    end
  end

  if update.sync then
    apply(M.read_sync(update.path))
  else
    M.read_async(update.path, apply)
  end
end

---@param update PeekstackPersistUpdate
local function enqueue(update)
  update_queue[#update_queue + 1] = update
  if not update_running then
    run_next_update()
  end
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
  enqueue({ path = path, mutate = mutate, on_done = on_done })
end

---Upper bound for waiting on queued updates ahead of a sync update.
local UPDATE_SYNC_TIMEOUT_MS = 1000

---Synchronously read, mutate and write back store data at `path`.
---The update joins the same queue as async updates, so it never overlaps an
---in-flight write. If earlier updates do not finish within
---UPDATE_SYNC_TIMEOUT_MS, the update is withdrawn and reported as failed
---rather than racing them with a write that one of them could later clobber.
---@param path string
---@param mutate fun(data: PeekstackStoreData): boolean
---@return boolean success whether the data was written
function M.update_sync(path, mutate)
  ---@type boolean?
  local result = nil
  ---@type PeekstackPersistUpdate
  local update = {
    path = path,
    mutate = mutate,
    sync = true,
    on_done = function(success)
      result = success
    end,
  }
  enqueue(update)

  if result == nil then
    vim.wait(UPDATE_SYNC_TIMEOUT_MS, function()
      return result ~= nil
    end, 10)
  end
  if result ~= nil then
    return result
  end

  -- A sync update runs to completion once dequeued, so a pending result means
  -- it is still queued behind a slow write.
  for i, queued in ipairs(update_queue) do
    if queued == update then
      table.remove(update_queue, i)
      break
    end
  end
  notify.warn("Timed out waiting for pending session writes: " .. path)
  return false
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
