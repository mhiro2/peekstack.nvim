local M = {}

---@return integer
local function current_time()
  return os.time()
end

---@return table
local function create_empty_data()
  return { version = 2, sessions = {} }
end

---@param items PeekstackSessionItem[]
---@return PeekstackStoreData
local function migrate_v1_to_v2(items)
  return {
    version = 2,
    sessions = {
      default = {
        items = items,
        meta = {
          created_at = current_time(),
          updated_at = current_time(),
        },
      },
    },
  }
end

---Coerce a single persisted session into the shape the rest of the persist
---layer assumes (`items` list + `meta` timestamps). Returns nil when the entry
---cannot be a session at all so the caller can drop it.
---@param session any
---@return PeekstackSession?
local function normalize_session(session)
  if type(session) ~= "table" then
    return nil
  end

  -- items must be a list; a dictionary would be silently skipped by ipairs.
  if type(session.items) ~= "table" or not vim.islist(session.items) then
    session.items = {}
  end

  -- meta must be a record; adding timestamps to a list would produce a
  -- mixed table that cannot be re-encoded as JSON.
  local meta = session.meta
  if type(meta) ~= "table" or (next(meta) ~= nil and vim.islist(meta)) then
    meta = {}
  end
  local now = current_time()
  if type(meta.created_at) ~= "number" then
    meta.created_at = now
  end
  if type(meta.updated_at) ~= "number" then
    meta.updated_at = meta.created_at
  end
  session.meta = meta

  return session
end

---Ensure data is in the correct format (migration helper)
---@param data any
---@return PeekstackStoreData
function M.ensure(data)
  if not data or type(data) ~= "table" then
    return create_empty_data()
  end

  -- Version 2: sessions format
  if data.version == 2 then
    if type(data.sessions) ~= "table" then
      data.sessions = {}
    end
    -- A hand-edited or partially written file may hold malformed entries;
    -- normalize them here so consumers never index into a non-table session.
    local sessions = {}
    for name, session in pairs(data.sessions) do
      local normalized = type(name) == "string" and normalize_session(session) or nil
      if normalized then
        sessions[name] = normalized
      end
    end
    data.sessions = sessions
    return data
  end

  -- Version 1: migrate items to sessions.default
  if data.version == 1 and type(data.items) == "table" then
    return migrate_v1_to_v2(data.items)
  end

  return create_empty_data()
end

return M
