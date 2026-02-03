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
    return data
  end

  -- Version 1: migrate items to sessions.default
  if data.version == 1 and type(data.items) == "table" then
    return migrate_v1_to_v2(data.items)
  end

  return create_empty_data()
end

return M
