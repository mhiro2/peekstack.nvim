local render_mod = require("peekstack.ui.render")
local preview = require("peekstack.ui.stack_view.preview")
local tree = require("peekstack.ui.stack_view.tree")
local str = require("peekstack.util.str")

local M = {}

local PREVIEW_LINE_MARKER = "│ "

---@type table<string, string>
local TITLE_HL_TO_SV = {
  PeekstackTitleProvider = "PeekstackStackViewProvider",
  PeekstackTitlePath = "PeekstackStackViewPath",
  PeekstackTitleIcon = "PeekstackStackViewIcon",
  PeekstackTitleLine = "PeekstackStackViewLine",
}

---@class PeekstackStackViewPipelineOpts
---@field items PeekstackPopupModel[]
---@field focused_id integer?
---@field filter string?
---@field win_width integer
---@field ui_path PeekstackConfigPath?
---@field location_text fun(popup: PeekstackPopupModel, max_width: integer?): string
---@field preview_line? fun(source_bufnr: integer?, line: integer, max_width: integer, preview_prefix: string): PeekstackStackViewPreviewLine?

---@param text string
---@param query string?
---@return boolean
local function matches_filter(text, query)
  if not query or query == "" then
    return true
  end
  return text:lower():find(query:lower(), 1, true) ~= nil
end

---@param popup PeekstackPopupModel
---@param opts PeekstackStackViewPipelineOpts
---@return string
local function filter_label(popup, opts)
  if popup.title then
    return popup.title
  end
  return opts.location_text(popup, nil)
end

---@param popup PeekstackPopupModel
---@param prefix string
---@param idx integer
---@param is_focused boolean
---@param ui_path PeekstackConfigPath
---@param win_width integer
---@param location_text fun(popup: PeekstackPopupModel, max_width: integer?): string
---@return string, PeekstackStackViewHighlight[]
local function build_entry_line(popup, prefix, idx, is_focused, ui_path, win_width, location_text)
  local max_label_width = math.max(win_width - vim.fn.strdisplaywidth(prefix), 0)
  if ui_path.max_width and ui_path.max_width > 0 then
    max_label_width = math.min(max_label_width, ui_path.max_width)
  end

  local label = nil
  local label_chunks = nil
  if popup.title_chunks then
    label_chunks = render_mod.truncate_chunks(popup.title_chunks, max_label_width)
    label = render_mod.title_text(label_chunks)
  elseif popup.title then
    label = str.truncate_middle(popup.title, max_label_width)
  else
    label = location_text(popup, max_label_width)
  end

  ---@type PeekstackStackViewHighlight[]
  local line_hls = {}
  local focus_marker = is_focused and "▶ " or "  "
  local pinned = popup.pinned and "• " or ""
  local index_str = string.format("%d. ", idx)
  local tree_guide = prefix:sub(#focus_marker + #index_str + #pinned + 1)

  if is_focused then
    table.insert(line_hls, { col_start = 0, col_end = #focus_marker, hl_group = "PeekstackStackViewFocused" })
  end

  local idx_start = #focus_marker
  table.insert(line_hls, {
    col_start = idx_start,
    col_end = idx_start + #index_str,
    hl_group = "PeekstackStackViewIndex",
  })

  if popup.pinned then
    local pin_start = idx_start + #index_str
    table.insert(line_hls, {
      col_start = pin_start,
      col_end = pin_start + #pinned,
      hl_group = "PeekstackStackViewPinned",
    })
  end

  if tree_guide ~= "" then
    local tree_start = idx_start + #index_str + #pinned
    table.insert(line_hls, {
      col_start = tree_start,
      col_end = tree_start + #tree_guide,
      hl_group = "PeekstackStackViewTree",
    })
  end

  if label_chunks then
    local pos = #prefix
    for _, chunk in ipairs(label_chunks) do
      local text = chunk[1] or ""
      local hl = chunk[2]
      if hl and #text > 0 then
        table.insert(line_hls, {
          col_start = pos,
          col_end = pos + #text,
          hl_group = TITLE_HL_TO_SV[hl] or hl,
        })
      end
      pos = pos + #text
    end
  end

  return prefix .. label, line_hls
end

---@param opts PeekstackStackViewPipelineOpts
---@return PeekstackStackViewRenderModel
function M.build(opts)
  local ui_path = opts.ui_path or {}
  local preview_line = opts.preview_line or preview.preview_line

  ---@type string[]
  local lines = {}
  ---@type PeekstackStackViewHighlight[][]
  local highlights = {}
  ---@type table<integer, PeekstackStackViewPreviewLine>
  local preview_lines = {}
  ---@type table<integer, integer>
  local line_to_id = {}

  ---@type PeekstackPopupModel[]
  local visible = {}
  for _, popup in ipairs(opts.items) do
    if matches_filter(filter_label(popup, opts), opts.filter) then
      table.insert(visible, popup)
    end
  end

  visible = tree.sort(visible)
  local tree_guides = tree.guide_by_id(visible)

  local header = nil
  local header_hl = nil
  if opts.filter and opts.filter ~= "" then
    header = string.format("Filter: %s (%d/%d)", opts.filter, #visible, #opts.items)
    header_hl = "PeekstackStackViewFilter"
  else
    header = string.format("Stack: %d", #visible)
    header_hl = "PeekstackStackViewHeader"
  end

  table.insert(lines, header)
  table.insert(highlights, { { col_start = 0, col_end = #header, hl_group = header_hl } })

  if #visible == 0 then
    local empty = opts.filter and opts.filter ~= "" and "No matches" or "No stack entries"
    table.insert(lines, empty)
    table.insert(highlights, { { col_start = 0, col_end = #empty, hl_group = "PeekstackStackViewEmpty" } })
  end

  for idx, popup in ipairs(visible) do
    local is_focused = popup.id == opts.focused_id
    local focus_marker = is_focused and "▶ " or "  "
    local pinned = popup.pinned and "• " or ""
    local index_str = string.format("%d. ", idx)
    local tree_guide = tree_guides[popup.id] or ""
    local prefix = focus_marker .. index_str .. pinned .. tree_guide

    local line, line_hls = build_entry_line(popup, prefix, idx, is_focused, ui_path, opts.win_width, opts.location_text)

    table.insert(lines, line)
    table.insert(highlights, line_hls)

    local entry_line_nr = #lines
    line_to_id[entry_line_nr] = popup.id

    local source_line = popup.location
      and popup.location.range
      and popup.location.range.start
      and popup.location.range.start.line
    if source_line then
      local preview_prefix = string.rep(" ", vim.fn.strdisplaywidth(prefix)) .. PREVIEW_LINE_MARKER
      local preview_item = preview_line(popup.source_bufnr or popup.bufnr, source_line, opts.win_width, preview_prefix)
      if preview_item then
        table.insert(lines, preview_item.line)
        table.insert(highlights, {
          { col_start = 0, col_end = #preview_item.line, hl_group = "PeekstackStackViewPreview" },
        })

        local preview_line_nr = #lines
        preview_lines[preview_line_nr] = preview_item
        line_to_id[preview_line_nr] = popup.id
      end
    end
  end

  return {
    lines = lines,
    highlights = highlights,
    preview_lines = preview_lines,
    line_to_id = line_to_id,
    header_lines = 1,
  }
end

return M
