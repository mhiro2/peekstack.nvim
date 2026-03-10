local config = require("peekstack.config")
local fs = require("peekstack.util.fs")
local notify = require("peekstack.util.notify")

local M = {}

--- Maximum number of lines to copy from the source buffer into a popup.
--- Files smaller than this are copied in full; larger files are windowed
--- around the target line to avoid blocking on huge buffers.
local MAX_VIEWPORT_LINES = 500

---Compute the line range to copy from source buffer.
---@param source_bufnr integer
---@param target_line integer 0-indexed target line
---@return integer start_line 0-indexed inclusive
---@return integer end_line 0-indexed exclusive (-1 means all)
---@return integer line_offset lines skipped from the start
function M.compute_viewport(source_bufnr, target_line)
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

---Resolve buffer_mode from opts or config.
---@param opts table
---@return "copy"|"source"
function M.resolve_buffer_mode(opts)
  if opts.buffer_mode then
    return opts.buffer_mode
  end
  return config.get().ui.popup.buffer_mode or "copy"
end

---@param location PeekstackLocation
---@param opts? table
---@return { bufnr: integer, source_bufnr: integer, buffer_mode: "copy"|"source", line_offset: integer }?
function M.prepare(location, opts)
  local buffer_mode = M.resolve_buffer_mode(opts or {})

  local ok_buf, fname = pcall(fs.uri_to_fname, location.uri)
  if not ok_buf or not fname then
    notify.warn("Failed to resolve file: " .. tostring(location.uri))
    return nil
  end

  local source_bufnr = vim.fn.bufadd(fname)
  if source_bufnr == 0 then
    notify.warn("Failed to add buffer: " .. fname)
    return nil
  end

  local ok_load = pcall(vim.fn.bufload, source_bufnr)
  if not ok_load then
    notify.warn("Failed to load buffer: " .. fname)
    return nil
  end

  if buffer_mode == "source" then
    return {
      bufnr = source_bufnr,
      source_bufnr = source_bufnr,
      buffer_mode = buffer_mode,
      line_offset = 0,
    }
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].readonly = false

  local target_line = location.range.start.line or 0
  local vp_start, vp_end, line_offset = M.compute_viewport(source_bufnr, target_line)
  local ok_lines, lines = pcall(vim.api.nvim_buf_get_lines, source_bufnr, vp_start, vp_end, false)
  if not ok_lines then
    notify.warn("Failed to read buffer contents: " .. fname)
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    return nil
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  configure_popup_buffer(bufnr, source_bufnr, opts)

  return {
    bufnr = bufnr,
    source_bufnr = source_bufnr,
    buffer_mode = buffer_mode,
    line_offset = line_offset,
  }
end

return M
