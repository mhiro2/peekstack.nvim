local M = {}
local notify = require("peekstack.util.notify")

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
  notify.debug(table.concat(vim.iter({ ... }):map(tostring):totable(), " "))
end

return M
