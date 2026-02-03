local M = {}

---@param msg string
function M.warn(msg)
  vim.notify("[peekstack] " .. msg, vim.log.levels.WARN)
end

---@param msg string
function M.info(msg)
  vim.notify("[peekstack] " .. msg, vim.log.levels.INFO)
end

return M
