local M = {}

---@type table<string, uv.uv_timer_t?>
local store = {}

---@return table<string, uv.uv_timer_t?>
function M.get_store()
  return store
end

---@param handle uv.uv_timer_t?
function M.close(handle)
  if not handle then
    return
  end
  pcall(function()
    handle:stop()
  end)
  local ok, is_closing = pcall(function()
    return handle:is_closing()
  end)
  if ok and is_closing then
    return
  end
  pcall(function()
    handle:close()
  end)
end

return M
