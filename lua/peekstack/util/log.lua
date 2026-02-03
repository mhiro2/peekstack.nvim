local M = {}

M.enabled = false

---@param val boolean
function M.set_enabled(val)
  M.enabled = val and true or false
end

---@param ... any
function M.debug(...)
  if not M.enabled then
    return
  end
  vim.notify(table.concat(vim.iter({ ... }):map(tostring):totable(), " "), vim.log.levels.DEBUG)
end

return M
