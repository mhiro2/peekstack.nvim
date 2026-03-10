local buffer = require("peekstack.core.popup.buffer")
local origin = require("peekstack.core.popup.origin")
local window = require("peekstack.core.popup.window")
local diagnostics_ui = require("peekstack.ui.diagnostics")
local keymaps = require("peekstack.ui.keymaps")

local M = {}

---@type integer
local next_id = 1

---@param location PeekstackLocation
---@param opts? { buffer_mode?: "copy"|"source", title?: string|PeekstackTitleChunk[], editable?: boolean, ephemeral?: boolean, origin_winid?: integer, parent_popup_id?: integer }
---@return PeekstackPopupModel?
function M.create(location, opts)
  opts = opts or {}
  local captured_origin = origin.capture(opts.origin_winid)
  local prepared = buffer.prepare(location, opts)
  if not prepared then
    return nil
  end

  opts.buffer_mode = prepared.buffer_mode

  local opened = window.open(prepared.bufnr, location, opts, prepared.line_offset)
  if not opened then
    if prepared.buffer_mode ~= "source" and vim.api.nvim_buf_is_valid(prepared.bufnr) then
      pcall(vim.api.nvim_buf_delete, prepared.bufnr, { force = true })
    end
    return nil
  end

  local id = opts.id or next_id
  if not opts.id then
    next_id = next_id + 1
  end

  local popup = {
    id = id,
    bufnr = prepared.bufnr,
    source_bufnr = prepared.source_bufnr,
    winid = opened.winid,
    location = location,
    origin = {
      winid = captured_origin.winid,
      bufnr = captured_origin.bufnr,
      row = captured_origin.row,
      col = captured_origin.col,
    },
    origin_bufnr = captured_origin.bufnr,
    origin_is_popup = origin.is_popup_origin(captured_origin),
    parent_popup_id = opts.parent_popup_id,
    title = opened.title,
    title_chunks = opened.title_chunks,
    pinned = false,
    buffer_mode = prepared.buffer_mode,
    line_offset = prepared.line_offset,
    created_at = os.time(),
    last_active_at = vim.uv.now(),
    ephemeral = opts.ephemeral or false,
    win_opts = opened.win_opts,
  }

  keymaps.apply_popup(popup)

  vim.b[prepared.bufnr].peekstack_popup_id = id
  vim.w[opened.winid].peekstack_popup_id = id

  popup.diagnostics = diagnostics_ui.decorate(popup)

  return popup
end

---@param popup PeekstackPopupModel
---@return boolean
function M.focus(popup)
  if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
    vim.api.nvim_set_current_win(popup.winid)
    return true
  end
  return false
end

---@param popup PeekstackPopupModel
function M.close(popup)
  -- Remove source-mode keymaps before closing the window so they do not
  -- leak into normal editing of the shared buffer.
  require("peekstack.ui.keymaps").remove_popup(popup)
  diagnostics_ui.clear(popup.diagnostics)
  if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
    vim.api.nvim_win_close(popup.winid, true)
  end
end

--- Reset next_id (for testing).
function M._reset()
  next_id = 1
end

return M
