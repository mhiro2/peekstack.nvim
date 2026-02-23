local M = {}

---@param msg string
---@param level integer
local function emit(msg, level)
  vim.notify("[peekstack] " .. msg, level)
end

---@param msg string
function M.warn(msg)
  emit(msg, vim.log.levels.WARN)
end

---@param msg string
function M.info(msg)
  emit(msg, vim.log.levels.INFO)
end

---@param msg string
function M.error(msg)
  emit(msg, vim.log.levels.ERROR)
end

---@param msg string
function M.debug(msg)
  emit(msg, vim.log.levels.DEBUG)
end

return M
