local M = {}

local NS = vim.api.nvim_create_namespace("peekstack_diagnostics")

---@class PeekstackDiagnosticExtmarks
---@field bufnr integer
---@field ns integer
---@field ids integer[]

---@param kind? integer
---@param prefix string "DiagnosticVirtualText" or "DiagnosticUnderline"
---@return string
local function severity_hl(kind, prefix)
  local suffix = ({
    [vim.diagnostic.severity.ERROR] = "Error",
    [vim.diagnostic.severity.WARN] = "Warn",
    [vim.diagnostic.severity.INFO] = "Info",
    [vim.diagnostic.severity.HINT] = "Hint",
  })[kind] or "Info"
  return prefix .. suffix
end

---@param text string
---@return string[]
local function split_message(text)
  local lines = vim.split(text, "\n", { plain = true })
  for i, line in ipairs(lines) do
    lines[i] = vim.trim(line)
  end
  return lines
end

---@param location PeekstackLocation
---@return boolean
local function is_diagnostic_location(location)
  return type(location.provider) == "string" and location.provider:match("^diagnostics%.") ~= nil
end

---@param bufnr integer
---@param row integer
---@return integer
local function row_length(bufnr, row)
  return #(vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or "")
end

---Map a diagnostic range onto the popup buffer, keeping only the part inside it.
---A range that starts above or ends below the buffer is clipped to its first or
---last line, and columns are clamped to each line's byte length.
---@param bufnr integer
---@param range table
---@param line_offset integer
---@return { row: integer, col: integer, end_row: integer, end_col: integer }?
local function underline_range(bufnr, range, line_offset)
  local last_row = vim.api.nvim_buf_line_count(bufnr) - 1
  local start = range.start or {}
  local finish = range["end"] or start
  local row = (start.line or 0) - line_offset
  local end_row = (finish.line or start.line or 0) - line_offset
  if end_row < 0 or row > last_row then
    return nil
  end

  local col = row < 0 and 0 or (start.character or 0)
  local end_col = end_row > last_row and math.huge or (finish.character or col)
  row = math.max(row, 0)
  end_row = math.min(end_row, last_row)
  col = math.min(math.max(col, 0), row_length(bufnr, row))
  end_col = math.min(math.max(end_col, 0), row_length(bufnr, end_row))
  -- Columns are only ordered within a single line.
  if end_row < row or (end_row == row and end_col < col) then
    end_row, end_col = row, col
  end
  return { row = row, col = col, end_row = end_row, end_col = end_col }
end

---@param popup PeekstackPopupModel
---@return PeekstackDiagnosticExtmarks?
function M.decorate(popup)
  if not popup or not popup.location then
    return nil
  end

  local location = popup.location
  if not is_diagnostic_location(location) then
    return nil
  end

  local text = location.text
  if not text or text == "" then
    return nil
  end

  local bufnr = popup.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return nil
  end

  local range = location.range or {}
  local line_offset = popup.line_offset or 0
  local start_row = ((range.start or {}).line or 0) - line_offset
  local line = math.min(math.max(start_row, 0), line_count - 1)
  local underline = underline_range(bufnr, range, line_offset)

  local ids = {}

  local virt_lines = {}
  local virt_hl = severity_hl(location.kind, "DiagnosticVirtualText")
  for _, msg in ipairs(split_message(text)) do
    local msg_text = msg ~= "" and msg or " "
    table.insert(virt_lines, { { msg_text, virt_hl } })
  end

  if #virt_lines > 0 then
    -- pcall guards against out-of-range coordinates raised by the API.
    local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, line, 0, {
      virt_lines = virt_lines,
      virt_lines_above = true,
    })
    if ok then
      table.insert(ids, id)
    end
  end

  if underline then
    local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, underline.row, underline.col, {
      end_row = underline.end_row,
      end_col = underline.end_col,
      hl_group = severity_hl(location.kind, "DiagnosticUnderline"),
    })
    if ok then
      table.insert(ids, id)
    end
  end

  if #ids == 0 then
    return nil
  end

  return { bufnr = bufnr, ns = NS, ids = ids }
end

---@param extmarks PeekstackDiagnosticExtmarks?
function M.clear(extmarks)
  if not extmarks or not extmarks.bufnr then
    return
  end
  if not vim.api.nvim_buf_is_valid(extmarks.bufnr) then
    return
  end
  for _, id in ipairs(extmarks.ids or {}) do
    pcall(vim.api.nvim_buf_del_extmark, extmarks.bufnr, extmarks.ns, id)
  end
end

return M
