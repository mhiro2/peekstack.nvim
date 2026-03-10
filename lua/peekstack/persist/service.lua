local config = require("peekstack.config")
local stack = require("peekstack.core.stack")
local location = require("peekstack.core.location")
local cache = require("peekstack.persist.cache")
local migrate = require("peekstack.persist.migrate")
local store = require("peekstack.persist.store")
local user_events = require("peekstack.core.user_events")
local notify = require("peekstack.util.notify")

local M = {}

local SCOPE = "repo"

---@param data PeekstackStoreData
---@return PeekstackStoreData
local function ensure_data(data)
  return migrate.ensure(data)
end

---Check if persistence is enabled, notify if not.
---@param silent? boolean
---@return boolean
local function ensure_enabled(silent)
  if not config.get().persist.enabled then
    if not silent then
      notify.info("peekstack.persist is disabled")
    end
    return false
  end
  return true
end

---@param name? string
---@return string
local function resolve_name(name)
  if name and name ~= "" then
    return name
  end

  local cfg = config.get()
  if cfg.persist.session and cfg.persist.session.default_name then
    return cfg.persist.session.default_name
  end

  return "default"
end

---@param root_winid? integer
---@return integer
local function resolve_root_winid(root_winid)
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

---@param root_winid? integer
---@return PeekstackSessionItem[]
local function collect_items(root_winid)
  local data_items = {}
  for _, popup in ipairs(stack.list(resolve_root_winid(root_winid))) do
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

---@param data PeekstackStoreData
---@param name string
---@param items PeekstackSessionItem[]
---@return PeekstackStoreData
local function upsert_session(data, name, items)
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

---@param read_data PeekstackStoreData
---@return PeekstackStoreData
local function update_cache(read_data)
  return cache.update(ensure_data(read_data))
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

  if not ensure_enabled(silent) then
    finish(false)
    return
  end

  local resolved_name = resolve_name(name)
  local items = collect_items(opts and opts.root_winid or nil)

  if sync then
    local data = upsert_session(ensure_data(store.read_sync(SCOPE)), resolved_name, items)
    local success = store.write_sync(SCOPE, data)
    if success then
      cache.update(data)
    end
    notify_save_result(success, resolved_name, items, silent)
    finish(success)
    return
  end

  store.read(SCOPE, {
    on_done = function(read_data)
      local data = upsert_session(ensure_data(read_data), resolved_name, items)
      store.write(SCOPE, data, {
        on_done = function(success)
          if success then
            cache.update(data)
          end
          notify_save_result(success, resolved_name, items, silent)
          finish(success)
        end,
      })
    end,
  })
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

  if not ensure_enabled(silent) then
    finish(false)
    return
  end

  local resolved_name = resolve_name(name)
  store.read(SCOPE, {
    on_done = function(read_data)
      local data = update_cache(read_data)
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
    end,
  })
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

  if not ensure_enabled(silent) then
    return {}
  end

  if on_done then
    store.read(SCOPE, {
      on_done = function(read_data)
        local data = update_cache(read_data)
        on_done(data.sessions or {})
      end,
    })
  elseif not cache.is_loaded() then
    update_cache(store.read_sync(SCOPE))
  end

  return cache.get()
end

---Delete a named session.
---@param name string
function M.delete_session(name)
  if not ensure_enabled() then
    return
  end

  store.read(SCOPE, {
    on_done = function(read_data)
      local data = ensure_data(read_data)

      if not data.sessions[name] then
        notify.warn("Session not found: " .. name)
        return
      end

      data.sessions[name] = nil
      store.write(SCOPE, data, {
        on_done = function(success)
          if success then
            cache.update(data)
            notify.info("Session deleted: " .. name)
            user_events.emit("PeekstackDeleteSession", {
              session = name,
            })
          else
            notify.warn("Failed to delete session: " .. name)
          end
        end,
      })
    end,
  })
end

---Rename a session.
---@param from string
---@param to string
function M.rename_session(from, to)
  if not ensure_enabled() then
    return
  end

  if from == to then
    notify.warn("Source and destination names are the same")
    return
  end

  store.read(SCOPE, {
    on_done = function(read_data)
      local data = ensure_data(read_data)

      if not data.sessions[from] then
        notify.warn("Session not found: " .. from)
        return
      end

      if data.sessions[to] then
        notify.warn("Target session already exists: " .. to)
        return
      end

      data.sessions[to] = data.sessions[from]
      data.sessions[from] = nil
      data.sessions[to].meta.updated_at = os.time()

      store.write(SCOPE, data, {
        on_done = function(success)
          if success then
            cache.update(data)
            notify.info("Session renamed: " .. from .. " -> " .. to)
            user_events.emit("PeekstackRenameSession", {
              from = from,
              to = to,
            })
          else
            notify.warn("Failed to rename session: " .. from .. " -> " .. to)
          end
        end,
      })
    end,
  })
end

---Reset in-memory session cache (for testing).
function M._reset_cache()
  cache.reset()
end

return M
