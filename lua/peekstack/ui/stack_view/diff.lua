local preview = require("peekstack.ui.stack_view.preview")

local M = {}

local NS = vim.api.nvim_create_namespace("PeekstackStackView")
local PREVIEW_BASE_HL_PRIORITY = 10

---@param line string
---@param line_hls PeekstackStackViewHighlight[]
---@param preview_line PeekstackStackViewPreviewLine?
---@return string
local function line_render_key(line, line_hls, preview_line)
  local parts = { line }
  for _, hl in ipairs(line_hls) do
    parts[#parts + 1] = string.format("%d:%d:%s", hl.col_start, hl.col_end, hl.hl_group)
  end
  if preview_line then
    parts[#parts + 1] = string.format(
      "preview:%d:%d:%d:%d:%d",
      preview_line.source_bufnr,
      preview_line.source_line,
      preview_line.source_col_start,
      preview_line.source_col_end,
      preview_line.preview_col_start
    )
  end
  return table.concat(parts, "|")
end

---@param items string[]
---@param start_idx integer
---@param end_idx integer
---@return string[]
local function slice_lines(items, start_idx, end_idx)
  if end_idx < start_idx then
    return {}
  end

  ---@type string[]
  local slice = {}
  for idx = start_idx, end_idx do
    slice[#slice + 1] = items[idx]
  end
  return slice
end

---@param old_keys string[]
---@param new_keys string[]
---@return integer?, integer?, integer?
local function diff_range(old_keys, new_keys)
  local old_count = #old_keys
  local new_count = #new_keys
  local start_idx = 1

  while start_idx <= old_count and start_idx <= new_count and old_keys[start_idx] == new_keys[start_idx] do
    start_idx = start_idx + 1
  end

  if start_idx > old_count and start_idx > new_count then
    return nil, nil, nil
  end

  local old_end = old_count
  local new_end = new_count
  while old_end >= start_idx and new_end >= start_idx and old_keys[old_end] == new_keys[new_end] do
    old_end = old_end - 1
    new_end = new_end - 1
  end

  return start_idx, old_end, new_end
end

---@param bufnr integer
---@param highlights PeekstackStackViewHighlight[][]
---@param preview_lines table<integer, PeekstackStackViewPreviewLine>
---@param start_idx integer
---@param end_idx integer
---@param preview_cache table<string, PeekstackStackViewPreviewTsHighlight[]|false>
local function apply_highlights_in_range(bufnr, highlights, preview_lines, start_idx, end_idx, preview_cache)
  if end_idx < start_idx then
    return
  end

  for line_idx = start_idx, end_idx do
    for _, hl in ipairs(highlights[line_idx] or {}) do
      local opts = {
        end_col = hl.col_end,
        hl_group = hl.hl_group,
      }
      if hl.hl_group == "PeekstackStackViewPreview" then
        opts.priority = PREVIEW_BASE_HL_PRIORITY
      end
      vim.api.nvim_buf_set_extmark(bufnr, NS, line_idx - 1, hl.col_start, {
        end_col = opts.end_col,
        hl_group = opts.hl_group,
        priority = opts.priority,
      })
    end
  end

  ---@type table<integer, PeekstackStackViewPreviewLine>
  local changed_previews = {}
  for line_idx = start_idx, end_idx do
    if preview_lines[line_idx] then
      changed_previews[line_idx] = preview_lines[line_idx]
    end
  end
  if next(changed_previews) then
    preview.apply_treesitter_highlights(bufnr, changed_previews, preview_cache)
  end
end

---@param model PeekstackStackViewRenderModel
---@return string[]
local function line_keys(model)
  ---@type string[]
  local keys = {}
  for line_idx, line in ipairs(model.lines) do
    keys[line_idx] = line_render_key(line, model.highlights[line_idx] or {}, model.preview_lines[line_idx])
  end
  return keys
end

---@param bufnr integer
---@param old_keys string[]
---@param model PeekstackStackViewRenderModel
---@param preview_cache table<string, PeekstackStackViewPreviewTsHighlight[]|false>
---@return string[]
function M.apply(bufnr, old_keys, model, preview_cache)
  local new_keys = line_keys(model)
  local start_idx, old_end, new_end = diff_range(old_keys, new_keys)
  if start_idx then
    local replace = slice_lines(model.lines, start_idx, new_end)

    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, start_idx - 1, old_end, false, replace)
    vim.bo[bufnr].modifiable = false

    vim.api.nvim_buf_clear_namespace(bufnr, NS, start_idx - 1, old_end)
    apply_highlights_in_range(bufnr, model.highlights, model.preview_lines, start_idx, new_end, preview_cache)
  end

  return new_keys
end

return M
