local stack = require("peekstack.core.stack")
local location = require("peekstack.core.location")
local orchestrator = require("peekstack.persist.orchestrator")
local sessions = require("peekstack.persist.sessions")
local user_events = require("peekstack.core.user_events")
local notify = require("peekstack.util.notify")

local M = {}

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
---@param opts? { root_winid?: integer, silent?: boolean, sync?: boolean, on_done?: fun(success: boolean) }
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

  if sync then
    local data = sessions.upsert(orchestrator.read_sync(), resolved_name, items)
    local success = orchestrator.write_sync(data)
    notify_save_result(success, resolved_name, items, silent)
    finish(success)
    return
  end

  orchestrator.read_async(function(read_data)
    local data = sessions.upsert(read_data, resolved_name, items)
    orchestrator.write_async(data, function(success)
      notify_save_result(success, resolved_name, items, silent)
      finish(success)
    end)
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
  orchestrator.refresh_cache_async(function(data)
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
    for _, item in ipairs(session.items) do
      local loc = location.normalize({ uri = item.uri, range = item.range }, item.provider or "persist")
      if loc then
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
        })
        if model then
          if item.pinned then
            model.pinned = true
          end
          if item.popup_id then
            id_remap[item.popup_id] = model.id
          end
        end
      end
    end

    stack.reflow()

    if not silent then
      notify.info("Session restored: " .. resolved_name)
    end

    user_events.emit("PeekstackRestore", {
      session = resolved_name,
      item_count = #session.items,
    })
    finish(true)
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

  if on_done then
    orchestrator.refresh_cache_async(function(data)
      on_done(data.sessions or {})
    end)
  elseif not orchestrator.cache_loaded() then
    orchestrator.refresh_cache_sync()
  end

  return orchestrator.cache_sessions()
end

---Delete a named session.
---@param name string
function M.delete_session(name)
  if not orchestrator.ensure_enabled() then
    return
  end

  orchestrator.read_async(function(data)
    if not sessions.delete(data, name) then
      notify.warn("Session not found: " .. name)
      return
    end

    orchestrator.write_async(data, function(success)
      if success then
        notify.info("Session deleted: " .. name)
        user_events.emit("PeekstackDeleteSession", {
          session = name,
        })
      else
        notify.warn("Failed to delete session: " .. name)
      end
    end)
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

  orchestrator.read_async(function(data)
    local result = sessions.rename(data, from, to)
    if not result.ok then
      if result.err == "missing" then
        notify.warn("Session not found: " .. from)
      elseif result.err == "exists" then
        notify.warn("Target session already exists: " .. to)
      end
      return
    end

    orchestrator.write_async(data, function(success)
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
  end)
end

---Reset in-memory session cache (for testing).
function M._reset_cache()
  orchestrator.reset_cache()
end

return M
