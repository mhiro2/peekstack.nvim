local fs = require("peekstack.util.fs")
local config = require("peekstack.config")
local user_events = require("peekstack.core.user_events")

local M = {}

---@param winid integer
---@param location PeekstackLocation
local function open_in_win(winid, location)
  local fname = fs.uri_to_fname(location.uri)
  local ok, bufnr = pcall(vim.fn.bufadd, fname)
  if not ok or not bufnr then
    vim.notify("Failed to add buffer: " .. fname, vim.log.levels.WARN)
    return
  end
  pcall(vim.fn.bufload, bufnr)
  vim.api.nvim_win_set_buf(winid, bufnr)
  local line = (location.range.start.line or 0) + 1
  local col = (location.range.start.character or 0)
  pcall(vim.api.nvim_win_set_cursor, winid, { line, col })
end

---@param popup PeekstackPopupModel
local function maybe_close_popup(popup)
  if config.get().ui.promote.close_popup then
    require("peekstack.core.stack").close(popup.id)
  end
end

---@param popup PeekstackPopupModel
---@param action string
---@param open_fn fun()
local function promote(popup, action, open_fn)
  local origin = popup.origin
  if origin and origin.winid and vim.api.nvim_win_is_valid(origin.winid) then
    vim.api.nvim_set_current_win(origin.winid)
  end

  open_fn()
  local new_winid = vim.api.nvim_get_current_win()
  open_in_win(new_winid, popup.location)

  user_events.emit("PeekstackPromote", {
    popup_id = popup.id,
    winid = new_winid,
    location = popup.location,
    provider = popup.location.provider,
    action = action,
  })

  maybe_close_popup(popup)
end

---@param popup PeekstackPopupModel
function M.split(popup)
  promote(popup, "split", function()
    vim.api.nvim_open_win(0, true, { split = "below" })
  end)
end

---@param popup PeekstackPopupModel
function M.vsplit(popup)
  promote(popup, "vsplit", function()
    vim.api.nvim_open_win(0, true, { split = "right" })
  end)
end

---@param popup PeekstackPopupModel
function M.tab(popup)
  promote(popup, "tab", function()
    vim.api.nvim_cmd({ cmd = "tabnew" }, {})
  end)
end

return M
