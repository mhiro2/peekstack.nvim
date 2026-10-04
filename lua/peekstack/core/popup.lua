local buffer = require("peekstack.core.popup.buffer")
local origin = require("peekstack.core.popup.origin")
local render = require("peekstack.ui.render")
local window = require("peekstack.core.popup.window")
local diagnostics_ui = require("peekstack.ui.diagnostics")
local keymaps = require("peekstack.ui.keymaps")
local viewport_ui = require("peekstack.ui.viewport")

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
    viewport = prepared.viewport,
    created_at = os.time(),
    last_active_at = vim.uv.now(),
    ephemeral = opts.ephemeral or false,
    win_opts = opened.win_opts,
  }

  keymaps.apply_popup(popup)

  vim.b[prepared.bufnr].peekstack_popup_id = id
  vim.w[opened.winid].peekstack_popup_id = id

  popup.diagnostics = diagnostics_ui.decorate(popup)
  popup.viewport_marks = viewport_ui.decorate(popup)

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
---@return boolean
local function shows_own_buffer(popup)
  return popup.winid ~= nil
    and vim.api.nvim_win_is_valid(popup.winid)
    and vim.api.nvim_win_get_buf(popup.winid) == popup.bufnr
end

---Point a retargeted popup at the cursor of its window and retitle it.
---@param popup PeekstackPopupModel
local function relocate(popup)
  local cursor = vim.api.nvim_win_get_cursor(popup.winid)
  local pos = { line = cursor[1] - 1, character = cursor[2] }
  popup.location = {
    uri = vim.uri_from_bufnr(popup.bufnr),
    range = { start = pos, ["end"] = pos },
    provider = popup.location.provider,
  }

  -- A title without chunks was set by the user; keep it.
  if popup.title_chunks then
    local title_chunks = render.build_title(popup.location)
    popup.title_chunks = title_chunks
    popup.title = title_chunks and render.title_text(title_chunks) or nil
    if popup.win_opts then
      popup.win_opts.title = title_chunks
      popup.win_opts.title_pos = title_chunks and "center" or nil
    end
    pcall(vim.api.nvim_win_set_config, popup.winid, {
      title = title_chunks or "",
      title_pos = title_chunks and "center" or nil,
    })
  end
end

---Release the decorations and source-mode keymaps a popup placed on its
---buffer. Safe to call after the window is gone or more than once.
---@param popup PeekstackPopupModel
function M.release(popup)
  -- Remove source-mode keymaps so they do not leak into normal editing of
  -- the shared buffer.
  keymaps.remove_popup(popup)
  diagnostics_ui.clear(popup.diagnostics)
  viewport_ui.clear(popup.viewport_marks)
  popup.diagnostics = nil
  popup.viewport_marks = nil
end

---@param popup PeekstackPopupModel
function M.close(popup)
  if popup.relocate_pending then
    popup.relocate_pending = nil
    if shows_own_buffer(popup) then
      relocate(popup)
    end
  end
  M.release(popup)
  if popup.winid and vim.api.nvim_win_is_valid(popup.winid) then
    vim.api.nvim_win_close(popup.winid, true)
  end
end

---Make a popup follow a buffer that replaced its own in the popup window
---(`:buffer`, `:edit`). The window now shows a regular buffer, so the popup
---becomes a source-mode popup at the cursor: provider requests, keymaps,
---title and history all refer to that buffer from now on.
---@param popup PeekstackPopupModel
---@param bufnr integer
function M.retarget(popup, bufnr)
  M.release(popup)
  local old_bufnr = popup.bufnr
  if vim.api.nvim_buf_is_valid(old_bufnr) and vim.b[old_bufnr].peekstack_popup_id == popup.id then
    vim.b[old_bufnr].peekstack_popup_id = nil
  end

  popup.bufnr = bufnr
  popup.source_bufnr = bufnr
  popup.buffer_mode = "source"
  popup.line_offset = 0
  popup.viewport = nil
  vim.b[bufnr].peekstack_popup_id = popup.id
  relocate(popup)

  -- BufWinEnter fires before the command places the cursor (`:edit +100`,
  -- the buffer's last position), so take the position again once it is done,
  -- or when the popup closes first (see M.close).
  local winid = popup.winid
  popup.relocate_pending = true
  vim.schedule(function()
    if popup.relocate_pending and shows_own_buffer(popup) and popup.winid == winid then
      popup.relocate_pending = nil
      relocate(popup)
      require("peekstack.ui.stack_view").refresh_all()
    end
  end)

  if winid == vim.api.nvim_get_current_win() then
    keymaps.apply_popup(popup)
  end
end

--- Reset next_id (for testing).
function M._reset()
  next_id = 1
end

return M
