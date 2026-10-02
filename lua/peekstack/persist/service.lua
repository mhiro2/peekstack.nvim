local stack = require("peekstack.core.stack")
local location = require("peekstack.core.location")
local orchestrator = require("peekstack.persist.orchestrator")
local sessions = require("peekstack.persist.sessions")
local user_events = require("peekstack.core.user_events")
local notify = require("peekstack.util.notify")

local M = {}

---Validate the coarse shape of a session item read from disk.
---Deeper structural validation (range fields) happens in location.normalize.
---@param item any
---@return boolean
local function is_valid_item(item)
  return type(item) == "table" and type(item.uri) == "string" and type(item.range) == "table"
end

---Restore a single session item into the current stack.
---Records the original->restored popup id mapping so children can re-link to
---their parent. Assumes the item already passed is_valid_item.
---@param item PeekstackSessionItem
---@param id_remap table<integer, integer>
---@param root_winid integer stack root frozen when the restore was requested
---@return boolean restored whether a popup was actually created
local function restore_item(item, id_remap, root_winid)
  local loc = location.normalize({ uri = item.uri, range = item.range }, item.provider or "persist")
  if not loc then
    return false
  end

  local parent_id = item.parent_popup_id
  if parent_id then
    if id_remap[parent_id] then
      parent_id = id_remap[parent_id]
    else
      -- Parent was not restored (e.g. trimmed by max_items).
      -- Drop the stale reference to avoid accidental collisions.
      parent_id = nil
    end
  end

  local model = stack.push(loc, {
    title = item.title,
    buffer_mode = item.buffer_mode,
    parent_popup_id = parent_id,
    defer_reflow = true,
    root_winid = root_winid,
  })
  if not model then
    return false
  end

  if item.pinned then
    model.pinned = true
  end
  if item.popup_id then
    id_remap[item.popup_id] = model.id
  end
  return true
end

---@param success boolean
---@param name string
---@param items PeekstackSessionItem[]
---@param silent boolean
local function notify_save_result(success, name, items, silent)
  if not silent then
    if success then
      notify.info("Session saved: " .. name)
    else
      notify.warn("Failed to save session: " .. name)
    end
  end

  if success then
    user_events.emit("PeekstackSave", {
      session = name,
      item_count = #items,
    })
  end
end

---Save the current stack to persistent storage with optional name.
---@param name? string
---`store_path` pins the store file; it defaults to the current repository's
---store, resolved when the save is requested.
---@param opts? { root_winid?: integer, store_path?: string, silent?: boolean, sync?: boolean, on_done?: fun(success: boolean) }
function M.save_current(name, opts)
  local silent = opts and opts.silent or false
  local sync = opts and opts.sync or false
  local on_done = opts and opts.on_done or nil
  local function finish(success)
    if on_done then
      on_done(success)
    end
  end

  if not orchestrator.ensure_enabled(silent) then
    finish(false)
    return
  end

  local resolved_name = sessions.resolve_name(name)
  local items = sessions.collect_items(opts and opts.root_winid or nil)
  local path = opts and opts.store_path or orchestrator.store_path()

  if sync then
    local success = orchestrator.update_sync(path, function(data)
      sessions.upsert(data, resolved_name, items)
      return true
    end)
    notify_save_result(success, resolved_name, items, silent)
    finish(success)
    return
  end

  orchestrator.update_async(path, function(data)
    sessions.upsert(data, resolved_name, items)
    return true
  end, function(success)
    notify_save_result(success, resolved_name, items, silent)
    finish(success)
  end)
end

---Restore a named session from persistent storage.
---@param name? string
---@param opts? { root_winid?: integer, silent?: boolean, on_done?: fun(restored: boolean) }
function M.restore(name, opts)
  local silent = opts and opts.silent or false
  local on_done = opts and opts.on_done or nil
  local function finish(restored)
    if on_done then
      on_done(restored)
    end
  end

  if not orchestrator.ensure_enabled(silent) then
    finish(false)
    return
  end

  local resolved_name = sessions.resolve_name(name)
  -- Freeze the target stack now: the read below is async and the user may
  -- move to another window before the session is restored.
  local root_winid = sessions.resolve_root_winid(opts and opts.root_winid or nil)
  orchestrator.refresh_cache_async(orchestrator.store_path(), function(data)
    local session = data.sessions[resolved_name]

    if not session or not session.items or #session.items == 0 then
      if not silent then
        notify.info("No saved session: " .. resolved_name)
      end
      finish(false)
      return
    end

    ---@type table<integer, integer>
    local id_remap = {}
    local restored_count = 0
    for _, item in ipairs(session.items) do
      -- Isolate each item: a single corrupt entry (bad type or a push failure)
      -- must not abort restoring the rest of the session.
      if is_valid_item(item) then
        local ok, restored = pcall(restore_item, item, id_remap, root_winid)
        if ok and restored then
          restored_count = restored_count + 1
        end
      end
    end

    if vim.api.nvim_win_is_valid(root_winid) then
      stack.reflow(root_winid)
    end

    local skipped = #session.items - restored_count

    if not silent then
      if skipped > 0 then
        notify.warn(string.format("Session restored with %d skipped item(s): %s", skipped, resolved_name))
      else
        notify.info("Session restored: " .. resolved_name)
      end
    end

    user_events.emit("PeekstackRestore", {
      session = resolved_name,
      item_count = restored_count,
    })
    finish(restored_count > 0)
  end)
end

---List all saved sessions.
---@param opts? { on_done?: fun(sessions: table<string, PeekstackSession>), silent?: boolean }
---@return table<string, PeekstackSession>
function M.list_sessions(opts)
  local on_done = opts and opts.on_done or nil
  local silent = opts and opts.silent
  if silent == nil then
    -- Synchronous list calls are mostly used for command completion.
    -- Keep them silent to avoid notification spam when persist is disabled.
    silent = on_done == nil
  end

  if not orchestrator.ensure_enabled(silent) then
    return {}
  end

  local path = orchestrator.store_path()
  if on_done then
    orchestrator.refresh_cache_async(path, function(data)
      on_done(data.sessions or {})
    end)
  elseif not orchestrator.cache_loaded(path) then
    orchestrator.refresh_cache_sync(path)
  end

  return orchestrator.cache_sessions(path)
end

---Delete a named session.
---@param name string
function M.delete_session(name)
  if not orchestrator.ensure_enabled() then
    return
  end

  local found = false
  orchestrator.update_async(orchestrator.store_path(), function(data)
    found = sessions.delete(data, name)
    if not found then
      notify.warn("Session not found: " .. name)
    end
    return found
  end, function(success)
    if not found then
      return
    end
    if success then
      notify.info("Session deleted: " .. name)
      user_events.emit("PeekstackDeleteSession", {
        session = name,
      })
    else
      notify.warn("Failed to delete session: " .. name)
    end
  end)
end

---Rename a session.
---@param from string
---@param to string
function M.rename_session(from, to)
  if not orchestrator.ensure_enabled() then
    return
  end

  if from == to then
    notify.warn("Source and destination names are the same")
    return
  end

  local renamed = false
  orchestrator.update_async(orchestrator.store_path(), function(data)
    local result = sessions.rename(data, from, to)
    renamed = result.ok
    if result.err == "missing" then
      notify.warn("Session not found: " .. from)
    elseif result.err == "exists" then
      notify.warn("Target session already exists: " .. to)
    end
    return renamed
  end, function(success)
    if not renamed then
      return
    end
    if success then
      notify.info("Session renamed: " .. from .. " -> " .. to)
      user_events.emit("PeekstackRenameSession", {
        from = from,
        to = to,
      })
    else
      notify.warn("Failed to rename session: " .. from .. " -> " .. to)
    end
  end)
end

---Reset in-memory session cache (for testing).
function M._reset_cache()
  orchestrator.reset_cache()
end

return M
