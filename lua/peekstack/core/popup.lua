local config = require("peekstack.config")
local fs = require("peekstack.util.fs")
local render = require("peekstack.ui.render")
local diagnostics_ui = require("peekstack.ui.diagnostics")
local keymaps = require("peekstack.ui.keymaps")

local M = {}

--- Maximum number of lines to copy from the source buffer into a popup.
--- Files smaller than this are copied in full; larger files are windowed
--- around the target line to avoid blocking on huge buffers.
local MAX_VIEWPORT_LINES = 500

---Compute the line range to copy from source buffer.
---@param source_bufnr integer
---@param target_line integer  0-indexed target line
---@return integer start_line  0-indexed inclusive
---@return integer end_line    0-indexed exclusive (-1 means all)
---@return integer line_offset lines skipped from the start
local function compute_viewport(source_bufnr, target_line)
  local total = vim.api.nvim_buf_line_count(source_bufnr)
  if total <= MAX_VIEWPORT_LINES then
    return 0, -1, 0
  end
  local half = math.floor(MAX_VIEWPORT_LINES / 2)
  local start_line = math.max(0, target_line - half)
  local end_line = math.min(total, start_line + MAX_VIEWPORT_LINES)
  if end_line - start_line < MAX_VIEWPORT_LINES then
    start_line = math.max(0, end_line - MAX_VIEWPORT_LINES)
  end
  return start_line, end_line, start_line
end

---@param bufnr integer
---@param source_bufnr integer
---@param opts? table
local function configure_popup_buffer(bufnr, source_bufnr, opts)
  fs.configure_buffer(bufnr)
  vim.bo[bufnr].filetype = vim.bo[source_bufnr].filetype

  local editable = config.get().ui.popup.editable
  if opts and opts.editable ~= nil then
    editable = opts.editable
  end

  vim.bo[bufnr].modifiable = editable
  vim.bo[bufnr].readonly = not editable
end

---@type integer
local next_id = 1

---@return { winid: integer, bufnr: integer, row: integer, col: integer }
local function capture_origin()
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local is_popup = vim.w[winid].peekstack_popup_id ~= nil
  return {
    winid = winid,
    bufnr = bufnr,
    row = cursor[1],
    col = cursor[2],
    is_popup = is_popup,
  }
end

---@param winid integer
---@param location PeekstackLocation
---@param line_offset? integer  lines skipped from the start of the source buffer
local function set_cursor(winid, location, line_offset)
  local line = (location.range.start.line or 0) + 1 - (line_offset or 0)
  local col = (location.range.start.character or 0)
  pcall(vim.api.nvim_win_set_cursor, winid, { math.max(1, line), col })
end

---Resolve buffer_mode from opts or config.
---@param opts table
---@return "copy"|"source"
local function resolve_buffer_mode(opts)
  if opts.buffer_mode then
    return opts.buffer_mode
  end
  return config.get().ui.popup.buffer_mode or "copy"
end

---@param winid integer
---@return { winid: integer, bufnr: integer, row: integer, col: integer, is_popup: boolean }
local function capture_origin_from_win(winid)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local cursor = vim.api.nvim_win_get_cursor(winid)
  local is_popup = vim.w[winid].peekstack_popup_id ~= nil
  return {
    winid = winid,
    bufnr = bufnr,
    row = cursor[1],
    col = cursor[2],
    is_popup = is_popup,
  }
end

---@param location PeekstackLocation
---@param opts? { buffer_mode?: "copy"|"source", title?: string, editable?: boolean, ephemeral?: boolean, origin_winid?: integer }
---@return PeekstackPopupModel?
function M.create(location, opts)
  opts = opts or {}
  local origin = capture_origin()
  if opts.origin_winid and vim.api.nvim_win_is_valid(opts.origin_winid) then
    origin = capture_origin_from_win(opts.origin_winid)
  end
  local origin_is_popup = false
  if
    origin.is_popup == true
    and vim.api.nvim_buf_is_valid(origin.bufnr)
    and vim.bo[origin.bufnr].buftype == "nofile"
    and vim.bo[origin.bufnr].bufhidden == "wipe"
  then
    origin_is_popup = true
  elseif vim.api.nvim_buf_is_valid(origin.bufnr) then
    local ft = vim.bo[origin.bufnr].filetype
    if ft == "peekstack-stack" or ft == "peekstack-stack-help" then
      origin_is_popup = true
    end
  end
  local buffer_mode = resolve_buffer_mode(opts)

  local ok_buf, fname = pcall(fs.uri_to_fname, location.uri)
  if not ok_buf or not fname then
    vim.notify("Failed to resolve file: " .. tostring(location.uri), vim.log.levels.WARN)
    return nil
  end

  local source_bufnr = vim.fn.bufadd(fname)
  local ok_load = pcall(vim.fn.bufload, source_bufnr)
  if not ok_load then
    vim.notify("Failed to load buffer: " .. fname, vim.log.levels.WARN)
    return nil
  end

  local bufnr
  local line_offset = 0

  if buffer_mode == "source" then
    -- Source mode: use the real buffer directly
    bufnr = source_bufnr
  else
    -- Copy mode (default): create scratch buffer with copied lines
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].readonly = false
    local target_line = location.range.start.line or 0
    local vp_start, vp_end, vp_offset = compute_viewport(source_bufnr, target_line)
    line_offset = vp_offset
    local ok_lines, lines = pcall(vim.api.nvim_buf_get_lines, source_bufnr, vp_start, vp_end, false)
    if not ok_lines then
      vim.notify("Failed to read buffer contents: " .. fname, vim.log.levels.WARN)
      return nil
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    configure_popup_buffer(bufnr, source_bufnr, opts)
  end

  local ok_win, winid, win_opts = pcall(render.open, bufnr, location, opts)
  if not ok_win or not winid then
    vim.notify("Failed to open popup window", vim.log.levels.WARN)
    return nil
  end

  local title = win_opts.title
  if opts.title and opts.title ~= "" then
    title = opts.title
    win_opts.title = opts.title
    win_opts.title_pos = "center"
    pcall(vim.api.nvim_win_set_config, winid, win_opts)
  end
  set_cursor(winid, location, line_offset)

  local id = next_id
  next_id = next_id + 1

  local popup = {
    id = id,
    bufnr = bufnr,
    source_bufnr = source_bufnr,
    winid = winid,
    location = location,
    origin = {
      winid = origin.winid,
      bufnr = origin.bufnr,
      row = origin.row,
      col = origin.col,
    },
    origin_bufnr = origin.bufnr,
    origin_is_popup = origin_is_popup,
    title = title,
    pinned = false,
    buffer_mode = buffer_mode,
    line_offset = line_offset,
    created_at = os.time(),
    last_active_at = vim.uv.now(),
    ephemeral = opts.ephemeral or false,
    win_opts = win_opts,
  }

  keymaps.apply_popup(popup)

  vim.b[bufnr].peekstack_popup_id = id
  vim.w[winid].peekstack_popup_id = id

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
