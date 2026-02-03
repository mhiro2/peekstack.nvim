local config = require("peekstack.config")
local fs = require("peekstack.util.fs")

local NS_NAME = "PeekstackInlinePreviewNS"

---@type PeekstackInlinePreviewState?
local state = nil
---@type integer
local request_id = 0

local M = {}

---Get or create the inline preview namespace
---@return integer
local function get_namespace()
  if not vim.api.nvim_get_namespaces()[NS_NAME] then
    vim.api.nvim_create_namespace(NS_NAME)
  end
  return vim.api.nvim_get_namespaces()[NS_NAME]
end

---Check if inline preview is currently open
---@return boolean
function M.is_open()
  return state ~= nil
end

---Close the inline preview
function M.close()
  if state then
    local bufnr = state.bufnr
    local extmark_id = state.extmark_id

    if vim.api.nvim_buf_is_valid(bufnr) then
      local ns = get_namespace()
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, extmark_id)
    end

    state = nil
  end
end

---Render preview lines from a location
---@param location PeekstackLocation
---@param max_lines integer
---@param cb fun(lines: string[])
function M.render_lines_async(location, max_lines, cb)
  local fname = fs.uri_to_fname(location.uri)
  if not fname or fname == "" then
    cb({ "-- Unable to read file --" })
    return
  end

  -- Fast path: if the buffer is already loaded, read from it directly
  local bufnr = vim.fn.bufnr(fname)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local start0 = math.max(0, location.range.start.line or 0)
    local end0 = start0 + max_lines
    local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start0, end0, false)
    if ok and lines and #lines > 0 then
      cb(lines)
      return
    end
  end

  local line = location.range.start.line or 0
  local start_line = line + 1
  local end_line = start_line + max_lines - 1
  local chunk_size = 8192
  local uv = vim.uv

  uv.fs_open(fname, "r", 438, function(open_err, fd)
    if open_err or not fd then
      cb({ "-- Unable to read file --" })
      return
    end

    local offset = 0
    local line_no = 0
    local carry = ""
    local result = {}
    local closed = false

    local function close_fd()
      if closed then
        return
      end
      closed = true
      uv.fs_close(fd, function() end)
    end

    local function finish(lines)
      close_fd()
      cb(lines)
    end

    local function on_read(read_err, data)
      if read_err then
        finish({ "-- Unable to read file --" })
        return
      end

      if not data or data == "" then
        if carry ~= "" then
          line_no = line_no + 1
          if line_no >= start_line and line_no <= end_line then
            table.insert(result, carry)
          end
        end
        if #result == 0 and line_no < start_line then
          finish({ "-- Line beyond end of file --" })
        else
          finish(result)
        end
        return
      end

      local chunk = carry .. data
      local from = 1
      while true do
        local nl = chunk:find("\n", from, true)
        if not nl then
          break
        end
        local text = chunk:sub(from, nl - 1)
        line_no = line_no + 1
        if line_no >= start_line and line_no <= end_line then
          table.insert(result, text)
        end
        if line_no >= end_line then
          finish(result)
          return
        end
        from = nl + 1
      end

      carry = chunk:sub(from)
      offset = offset + #data
      uv.fs_read(fd, chunk_size, offset, on_read)
    end

    uv.fs_read(fd, chunk_size, offset, on_read)
  end)
end

---Open an inline preview for a location
---@param location PeekstackLocation
---@param opts? table
function M.open(location, opts)
  opts = opts or {}

  local cfg = config.get()
  if not cfg.ui.inline_preview or not cfg.ui.inline_preview.enabled then
    vim.notify("Inline preview is disabled", vim.log.levels.INFO)
    return
  end

  -- Close any existing preview
  M.close()

  local current_bufnr = vim.api.nvim_get_current_buf()
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1

  local max_lines = cfg.ui.inline_preview.max_lines or 10
  local hl_group = cfg.ui.inline_preview.hl_group or "PeekstackInlinePreview"

  request_id = request_id + 1
  local current_request = request_id
  local ns = get_namespace()

  local extmark_id = vim.api.nvim_buf_set_extmark(current_bufnr, ns, cursor_row, 0, {
    virt_lines = { { { "Loading... ", hl_group } } },
    virt_lines_above = true,
  })

  state = {
    bufnr = current_bufnr,
    extmark_id = extmark_id,
    target_uri = location.uri,
    created_at = os.time(),
    request_id = current_request,
  }

  -- Setup close events
  M.setup_close_events()

  M.render_lines_async(location, max_lines, function(lines)
    vim.schedule(function()
      if not state or state.request_id ~= current_request then
        return
      end
      if not vim.api.nvim_buf_is_valid(current_bufnr) then
        M.close()
        return
      end

      local virt_lines = {}
      for _, line in ipairs(lines) do
        table.insert(virt_lines, { { line .. " ", hl_group } })
      end

      if vim.api.nvim_buf_is_valid(current_bufnr) then
        pcall(vim.api.nvim_buf_del_extmark, current_bufnr, ns, state.extmark_id)
        state.extmark_id = vim.api.nvim_buf_set_extmark(current_bufnr, ns, cursor_row, 0, {
          virt_lines = virt_lines,
          virt_lines_above = true,
        })
      end
    end)
  end)
end

---Setup autocmds to close inline preview
function M.setup_close_events()
  local cfg = config.get()
  local close_events = cfg.ui.inline_preview.close_events or { "CursorMoved", "InsertEnter", "BufLeave", "WinLeave" }

  local group = vim.api.nvim_create_augroup("PeekstackInlinePreview", { clear = true })

  for _, event in ipairs(close_events) do
    vim.api.nvim_create_autocmd(event, {
      group = group,
      callback = function()
        M.close()
      end,
      once = true,
    })
  end
end

return M
