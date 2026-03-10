local service = require("peekstack.persist.service")

local M = {}

M.save_current = service.save_current
M.restore = service.restore
M.list_sessions = service.list_sessions
M.delete_session = service.delete_session
M.rename_session = service.rename_session
M._reset_cache = service._reset_cache

return M
