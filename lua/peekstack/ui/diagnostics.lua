local M = {}

local NS = vim.api.nvim_create_namespace("peekstack_diagnostics")

---@class PeekstackDiagnosticExtmarks
---@field bufnr integer
---@field ns integer
---@field ids integer[]

---@param kind? integer
---@return string
local function virtual_text_hl(kind)
  if kind == vim.diagnostic.severity.ERROR then
    return "DiagnosticVirtualTextError"
  end
  if kind == vim.diagnostic.severity.WARN then
    return "DiagnosticVirtualTextWarn"
  end
  if kind == vim.diagnostic.severity.INFO then
    return "DiagnosticVirtualTextInfo"
  end
  if kind == vim.diagnostic.severity.HINT then
    return "DiagnosticVirtualTextHint"
  end
  return "DiagnosticVirtualTextInfo"
end

---@param kind? integer
---@return string
local function underline_hl(kind)
  if kind == vim.diagnostic.severity.ERROR then
    return "DiagnosticUnderlineError"
  end
  if kind == vim.diagnostic.severity.WARN then
    return "DiagnosticUnderlineWarn"
  end
  if kind == vim.diagnostic.severity.INFO then
    return "DiagnosticUnderlineInfo"
  end
  if kind == vim.diagnostic.severity.HINT then
    return "DiagnosticUnderlineHint"
  end
  return "DiagnosticUnderlineInfo"
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

  local range = location.range or {}
  local start = range.start or {}
  local finish = range["end"] or start
  local line_offset = popup.line_offset or 0
  local line = (start.line or 0) - line_offset
  local col = start.character or 0
  local end_line = (finish.line or start.line or 0) - line_offset
  local end_col = finish.character or col

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return nil
  end

  line = math.min(math.max(line, 0), line_count - 1)
  end_line = math.min(math.max(end_line, line), line_count - 1)
  col = math.max(col, 0)
  end_col = math.max(end_col, col)

  local ids = {}

  local virt_lines = {}
  local virt_hl = virtual_text_hl(location.kind)
  for _, msg in ipairs(split_message(text)) do
    local msg_text = msg ~= "" and msg or " "
    table.insert(virt_lines, { { msg_text, virt_hl } })
  end

  if #virt_lines > 0 then
    local id = vim.api.nvim_buf_set_extmark(bufnr, NS, line, 0, {
      virt_lines = virt_lines,
      virt_lines_above = true,
    })
    table.insert(ids, id)
  end

  local underline = underline_hl(location.kind)
  if underline ~= "" then
    local id = vim.api.nvim_buf_set_extmark(bufnr, NS, line, col, {
      end_row = end_line,
      end_col = end_col,
      hl_group = underline,
    })
    table.insert(ids, id)
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
