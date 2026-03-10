local notify = require("peekstack.util.notify")

local M = {}

---@return PeekstackStoreData
function M.empty_data()
  return { version = 2, sessions = {} }
end

---@param data PeekstackStoreData
---@return string?
function M.encode(data)
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    notify.warn("Failed to encode session data")
    return nil
  end
  return encoded
end

---@param path string
---@param data string?
---@return PeekstackStoreData
function M.decode(path, data)
  if not data or data == "" then
    return M.empty_data()
  end

  local ok, decoded = pcall(vim.json.decode, data)
  if not ok or type(decoded) ~= "table" then
    notify.warn("Failed to decode session data: " .. path)
    return M.empty_data()
  end

  return decoded
end

return M
