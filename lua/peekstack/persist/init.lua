local config = require("peekstack.config")
local stack = require("peekstack.core.stack")
local location = require("peekstack.core.location")
local store = require("peekstack.persist.store")
local migrate = require("peekstack.persist.migrate")
local user_events = require("peekstack.core.user_events")

local M = {}

local SCOPE = "repo"

---Check if persistence is enabled, notify if not
---@return boolean
---@param silent? boolean
---@return boolean
local function ensure_enabled(silent)
  if not config.get().persist.enabled then
    if not silent then
      vim.notify("peekstack.persist is disabled", vim.log.levels.INFO)
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

---Save the current stack to persistent storage with optional name
---@param name? string
---@param opts? { scope?: string, root_winid?: integer, silent?: boolean }
function M.save_current(name, opts)
  local silent = opts and opts.silent or false
  if not ensure_enabled(silent) then
    return
  end

  local resolved_name = resolve_name(name)
  local scope = SCOPE

  local items = stack.list(resolve_root_winid(opts and opts.root_winid or nil))
  local data_items = {}
  for _, popup in ipairs(items) do
    table.insert(data_items, {
      uri = popup.location.uri,
      range = popup.location.range,
      title = popup.title,
      provider = popup.location.provider,
      ts = os.time(),
    })
  end

  local max_items = config.get().persist.max_items or 200
  if #data_items > max_items then
    data_items = vim.list_slice(data_items, #data_items - max_items + 1, #data_items)
  end

  local data = migrate.ensure(store.read(scope))
  local now = os.time()

  if data.sessions[resolved_name] then
    data.sessions[resolved_name].items = data_items
    data.sessions[resolved_name].meta.updated_at = now
  else
    data.sessions[resolved_name] = {
      items = data_items,
      meta = {
        created_at = now,
        updated_at = now,
      },
    }
  end

  store.write(scope, data)
  if not silent then
    vim.notify("Session saved: " .. resolved_name, vim.log.levels.INFO)
  end

  user_events.emit("PeekstackSave", {
    session = resolved_name,
    item_count = #data_items,
  })
end

---Restore a named session from persistent storage
---@param name? string
---@param opts? { scope?: string, root_winid?: integer, silent?: boolean }
function M.restore(name, opts)
  local silent = opts and opts.silent or false
  if not ensure_enabled(silent) then
    return
  end

  local resolved_name = resolve_name(name)
  local scope = SCOPE
  local data = migrate.ensure(store.read(scope))

  if
    not data.sessions[resolved_name]
    or not data.sessions[resolved_name].items
    or #data.sessions[resolved_name].items == 0
  then
    if not silent then
      vim.notify("No saved session: " .. resolved_name, vim.log.levels.INFO)
    end
    return
  end

  for _, item in ipairs(data.sessions[resolved_name].items) do
    local loc = location.normalize({ uri = item.uri, range = item.range }, item.provider or "persist")
    if loc then
      stack.push(loc, { title = item.title })
    end
  end

  if not silent then
    vim.notify("Session restored: " .. resolved_name, vim.log.levels.INFO)
  end

  user_events.emit("PeekstackRestore", {
    session = resolved_name,
    item_count = #data.sessions[resolved_name].items,
  })
end

---List all saved sessions
---@return table<string, PeekstackSession>
function M.list_sessions()
  return migrate.ensure(store.read(SCOPE)).sessions or {}
end

---Delete a named session
---@param name string
function M.delete_session(name)
  if not ensure_enabled() then
    return
  end

  local scope = SCOPE
  local data = migrate.ensure(store.read(scope))

  if not data.sessions[name] then
    vim.notify("Session not found: " .. name, vim.log.levels.WARN)
    return
  end

  data.sessions[name] = nil
  store.write(scope, data)
  vim.notify("Session deleted: " .. name, vim.log.levels.INFO)

  user_events.emit("PeekstackDeleteSession", {
    session = name,
  })
end

---Rename a session
---@param from string
---@param to string
function M.rename_session(from, to)
  if not ensure_enabled() then
    return
  end

  if from == to then
    vim.notify("Source and destination names are the same", vim.log.levels.WARN)
    return
  end

  local scope = SCOPE
  local data = migrate.ensure(store.read(scope))

  if not data.sessions[from] then
    vim.notify("Session not found: " .. from, vim.log.levels.WARN)
    return
  end

  if data.sessions[to] then
    vim.notify("Target session already exists: " .. to, vim.log.levels.WARN)
    return
  end

  data.sessions[to] = data.sessions[from]
  data.sessions[from] = nil
  data.sessions[to].meta.updated_at = os.time()

  store.write(scope, data)
  vim.notify("Session renamed: " .. from .. " -> " .. to, vim.log.levels.INFO)

  user_events.emit("PeekstackRenameSession", {
    from = from,
    to = to,
  })
end

return M
