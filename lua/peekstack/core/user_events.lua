local notify = require("peekstack.util.notify")

local M = {}

---Build event data from a popup model
---@param popup_model PeekstackPopupModel
---@param root_winid integer
---@param extra? table
---@return PeekstackUserEventData
function M.build_popup_data(popup_model, root_winid, extra)
  local data = {
    popup_id = popup_model.id,
    winid = popup_model.winid,
    bufnr = popup_model.bufnr,
    location = popup_model.location,
    provider = popup_model.location.provider,
    root_winid = root_winid,
  }
  if extra then
    data = vim.tbl_extend("force", data, extra)
  end
  return data
end

---Emit a User autocmd event for external plugins
---@param event string
---@param data PeekstackUserEventData
function M.emit(event, data)
  data = data or {}
  data.event = event

  local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = event,
    data = data,
  })

  if not ok then
    notify.warn("Failed to emit event " .. event .. ": " .. tostring(err))
  end
end

return M
