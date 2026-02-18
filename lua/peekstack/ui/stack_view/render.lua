local config = require("peekstack.config")
local location = require("peekstack.core.location")
local render_mod = require("peekstack.ui.render")
local tree = require("peekstack.ui.stack_view.tree")
local str = require("peekstack.util.str")

local M = {}

local NS = vim.api.nvim_create_namespace("PeekstackStackView")
local TS_HL_PRIORITY = 150
local PREVIEW_BASE_HL_PRIORITY = 10
local PREVIEW_LINE_MARKER = "│ "

---@type table<string, boolean>
local PREVIEW_ALLOWED_CAPTURE_PREFIX = {
  keyword = true,
  string = true,
  number = true,
  boolean = true,
  constant = true,
  ["function"] = true,
  method = true,
  constructor = true,
  type = true,
  comment = true,
  character = true,
}

---@type table<string, vim.treesitter.Query|false>
local TS_HIGHLIGHT_QUERY_CACHE = {}

---Map title highlight groups to their stack view equivalents
---@type table<string, string>
local TITLE_HL_TO_SV = {
  PeekstackTitleProvider = "PeekstackStackViewProvider",
  PeekstackTitlePath = "PeekstackStackViewPath",
  PeekstackTitleIcon = "PeekstackStackViewIcon",
  PeekstackTitleLine = "PeekstackStackViewLine",
}

---@class PeekstackStackViewHighlight
---@field col_start integer
---@field col_end integer
---@field hl_group string

---@class PeekstackStackViewPreviewLine
---@field line string
---@field source_bufnr integer
---@field source_line integer
---@field source_col_start integer
---@field source_col_end integer
---@field preview_col_start integer

---@class PeekstackStackViewParserCacheEntry
---@field trees TSTree[]
---@field fallback_lang string?

---@param lang string
---@return vim.treesitter.Query?
local function get_treesitter_highlight_query(lang)
  local cached = TS_HIGHLIGHT_QUERY_CACHE[lang]
  if cached ~= nil then
    return cached or nil
  end
  local ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
  if not ok or not query then
    TS_HIGHLIGHT_QUERY_CACHE[lang] = false
    return nil
  end
  TS_HIGHLIGHT_QUERY_CACHE[lang] = query
  return query
end

---@param bufnr integer
---@return PeekstackStackViewParserCacheEntry|false
local function build_parser_cache_entry(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return false
  end

  local ok_parse = pcall(function()
    parser:parse()
  end)
  if not ok_parse then
    return false
  end

  local trees = parser:trees()
  if type(trees) ~= "table" or next(trees) == nil then
    return false
  end

  local fallback_lang = nil
  local ft = vim.bo[bufnr].filetype
  if ft ~= "" then
    local ok_map, mapped = pcall(vim.treesitter.language.get_lang, ft)
    if ok_map and type(mapped) == "string" and mapped ~= "" then
      fallback_lang = mapped
    else
      fallback_lang = ft
    end
  end

  return {
    trees = trees,
    fallback_lang = fallback_lang,
  }
end

---@param parser_cache table<integer, PeekstackStackViewParserCacheEntry|false>
---@param bufnr integer
---@return PeekstackStackViewParserCacheEntry?
local function get_parser_cache_entry(parser_cache, bufnr)
  local cached = parser_cache[bufnr]
  if cached ~= nil then
    return cached or nil
  end

  local entry = build_parser_cache_entry(bufnr)
  parser_cache[bufnr] = entry
  return entry or nil
end

---@param entry PeekstackStackViewParserCacheEntry
---@param line integer
---@return TSNode?, string?
local function treesitter_root_for_line(entry, line)
  local root = nil
  local lang = nil
  local smallest_range = math.huge

  for _, tree_item in ipairs(entry.trees) do
    local candidate = tree_item:root()
    if candidate then
      local sr, _, er, _ = candidate:range()
      if line >= sr and line <= er then
        local range_size = er - sr
        if range_size < smallest_range then
          smallest_range = range_size
          root = candidate

          local ok_lang, tree_lang = pcall(function()
            return tree_item:lang()
          end)
          if ok_lang and type(tree_lang) == "string" and tree_lang ~= "" then
            lang = tree_lang
          else
            lang = entry.fallback_lang
          end
        end
      end
    end
  end

  if not root then
    return nil, nil
  end

  return root, lang
end

---@param name string
---@return boolean
local function highlight_exists(name)
  if name == "" then
    return false
  end
  return vim.fn.hlexists(name) == 1
end

---@param capture_name string?
---@param lang string?
---@return string?
local function capture_hl_group(capture_name, lang)
  if type(capture_name) ~= "string" or capture_name == "" then
    return nil
  end

  local capture_prefix = capture_name:match("^[^%.]+") or capture_name
  if not PREVIEW_ALLOWED_CAPTURE_PREFIX[capture_prefix] then
    return nil
  end

  if lang and lang ~= "" then
    local lang_group = string.format("@%s.%s", capture_name, lang)
    if highlight_exists(lang_group) then
      return lang_group
    end
  end

  local base_group = "@" .. capture_name
  if highlight_exists(base_group) then
    return base_group
  end

  return nil
end

---@param target_bufnr integer
---@param preview_line_nr integer
---@param preview PeekstackStackViewPreviewLine
---@param parser_cache table<integer, PeekstackStackViewParserCacheEntry|false>
local function apply_preview_treesitter_highlight(target_bufnr, preview_line_nr, preview, parser_cache)
  local source_bufnr = preview.source_bufnr
  if not source_bufnr or not vim.api.nvim_buf_is_valid(source_bufnr) then
    return
  end

  local source_line = preview.source_line
  local source_start = preview.source_col_start
  local source_end = preview.source_col_end
  if source_end <= source_start then
    return
  end

  local parser_entry = get_parser_cache_entry(parser_cache, source_bufnr)
  if not parser_entry then
    return
  end

  local root, lang = treesitter_root_for_line(parser_entry, source_line)
  if not root or not lang then
    return
  end

  local query = get_treesitter_highlight_query(lang)
  if not query then
    return
  end

  local ok_iter = pcall(function()
    for capture_id, node in query:iter_captures(root, source_bufnr, source_line, source_line + 1) do
      local hl_group = capture_hl_group(query.captures[capture_id], lang)
      if hl_group then
        local sr, sc, er, ec = node:range()
        if source_line >= sr and source_line <= er then
          local node_start = (sr == source_line) and sc or 0
          local node_end = (er == source_line) and ec or source_end
          local start_col = math.max(node_start, source_start)
          local end_col = math.min(node_end, source_end)
          if end_col > start_col then
            local view_start = preview.preview_col_start + (start_col - source_start)
            local view_end = preview.preview_col_start + (end_col - source_start)
            vim.api.nvim_buf_set_extmark(target_bufnr, NS, preview_line_nr - 1, view_start, {
              end_col = view_end,
              hl_group = hl_group,
              priority = TS_HL_PRIORITY,
            })
          end
        end
      end
    end
  end)

  if not ok_iter then
    return
  end
end

---@param target_bufnr integer
---@param previews table<integer, PeekstackStackViewPreviewLine>
local function apply_preview_treesitter_highlights(target_bufnr, previews)
  ---@type table<integer, PeekstackStackViewParserCacheEntry|false>
  local parser_cache = {}
  for preview_line_nr, preview in pairs(previews) do
    apply_preview_treesitter_highlight(target_bufnr, preview_line_nr, preview, parser_cache)
  end
end

---Get a trimmed preview line from a source buffer.
---@param source_bufnr integer?
---@param line integer
---@param max_width integer
---@param preview_prefix string
---@return PeekstackStackViewPreviewLine?
local function get_preview_line(source_bufnr, line, max_width, preview_prefix)
  if not source_bufnr or not vim.api.nvim_buf_is_valid(source_bufnr) then
    return nil
  end

  local ok, buf_lines = pcall(vim.api.nvim_buf_get_lines, source_bufnr, line, line + 1, false)
  if not ok or not buf_lines or #buf_lines == 0 then
    return nil
  end

  local source_text = buf_lines[1] or ""
  if source_text == "" then
    return nil
  end

  local source_col_start = #(source_text:match("^%s*") or "")
  local source_col_end = #source_text - #(source_text:match("%s*$") or "")
  if source_col_end <= source_col_start then
    return nil
  end

  local text = source_text:sub(source_col_start + 1, source_col_end)
  local prefix_display_width = vim.fn.strdisplaywidth(preview_prefix)
  local available = math.max(10, max_width - prefix_display_width)
  if vim.fn.strdisplaywidth(text) > available then
    local keep_chars = math.max(available - 3, 0)
    local kept = vim.fn.strcharpart(text, 0, keep_chars)
    text = kept .. "..."
    source_col_end = source_col_start + #kept
  end

  return {
    line = preview_prefix .. text,
    source_bufnr = source_bufnr,
    source_line = line,
    source_col_start = source_col_start,
    source_col_end = source_col_end,
    preview_col_start = #preview_prefix,
  }
end

---@param line string
---@param line_hls PeekstackStackViewHighlight[]
---@param preview PeekstackStackViewPreviewLine?
---@return string
local function line_render_key(line, line_hls, preview)
  local parts = { line }
  for _, hl in ipairs(line_hls) do
    parts[#parts + 1] = string.format("%d:%d:%s", hl.col_start, hl.col_end, hl.hl_group)
  end
  if preview then
    parts[#parts + 1] = string.format(
      "preview:%d:%d:%d:%d:%d",
      preview.source_bufnr,
      preview.source_line,
      preview.source_col_start,
      preview.source_col_end,
      preview.preview_col_start
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
local function apply_highlights_in_range(bufnr, highlights, preview_lines, start_idx, end_idx)
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
    apply_preview_treesitter_highlights(bufnr, changed_previews)
  end
end

---@param s PeekstackStackViewState
---@param is_ready fun(s: PeekstackStackViewState): boolean
function M.render(s, is_ready)
  if not is_ready(s) then
    return
  end

  local stack = require("peekstack.core.stack")
  local items = stack.list(s.root_winid)
  local ui_path = config.get().ui.path or {}
  local win_width = vim.api.nvim_win_get_width(s.winid)
  if win_width <= 0 then
    win_width = vim.o.columns
  end

  ---@type string[]
  local lines = {}
  ---@type PeekstackStackViewHighlight[][]
  local highlights = {}
  ---@type table<integer, PeekstackStackViewPreviewLine>
  local preview_lines = {}

  s.line_to_id = {}
  s.header_lines = 0

  ---@type PeekstackPopupModel[]
  local visible = {}
  for _, popup in ipairs(items) do
    local filter_label = popup.title
      or location.display_text(popup.location, 0, {
        path_base = ui_path.base,
      })
    if not s.filter or s.filter == "" or filter_label:lower():find(s.filter:lower(), 1, true) ~= nil then
      table.insert(visible, popup)
    end
  end

  visible = tree.sort(visible)
  local tree_guides = tree.guide_by_id(visible)

  local header = nil
  local header_hl = nil
  if s.filter and s.filter ~= "" then
    header = string.format("Filter: %s (%d/%d)", s.filter, #visible, #items)
    header_hl = "PeekstackStackViewFilter"
  else
    header = string.format("Stack: %d", #visible)
    header_hl = "PeekstackStackViewHeader"
  end

  table.insert(lines, header)
  table.insert(highlights, { { col_start = 0, col_end = #header, hl_group = header_hl } })
  s.header_lines = 1

  if #visible == 0 then
    local empty = s.filter and s.filter ~= "" and "No matches" or "No stack entries"
    table.insert(lines, empty)
    table.insert(highlights, { { col_start = 0, col_end = #empty, hl_group = "PeekstackStackViewEmpty" } })
  end

  local focused_id = stack.focused_id(s.root_winid)

  for idx, popup in ipairs(visible) do
    local is_focused = popup.id == focused_id
    local focus_marker = is_focused and "▶ " or "  "
    local pinned = popup.pinned and "• " or ""
    local index_str = string.format("%d. ", idx)
    local tree_guide = tree_guides[popup.id] or ""
    local prefix = focus_marker .. index_str .. pinned .. tree_guide

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
      label = location.display_text(popup.location, 0, {
        path_base = ui_path.base,
        max_width = max_label_width,
      })
    end

    local line = prefix .. label
    table.insert(lines, line)

    local entry_line_nr = #lines
    ---@type PeekstackStackViewHighlight[]
    local line_hls = {}

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

    table.insert(highlights, line_hls)
    s.line_to_id[entry_line_nr] = popup.id

    local source_line = popup.location
      and popup.location.range
      and popup.location.range.start
      and popup.location.range.start.line
    if source_line then
      local preview_prefix = string.rep(" ", vim.fn.strdisplaywidth(prefix)) .. PREVIEW_LINE_MARKER
      local preview = get_preview_line(popup.source_bufnr or popup.bufnr, source_line, win_width, preview_prefix)
      if preview then
        table.insert(lines, preview.line)
        local preview_line_nr = #lines
        table.insert(highlights, {
          { col_start = 0, col_end = #preview.line, hl_group = "PeekstackStackViewPreview" },
        })
        preview_lines[preview_line_nr] = preview
        s.line_to_id[preview_line_nr] = popup.id
      end
    end
  end

  ---@type string[]
  local line_keys = {}
  for line_idx, line in ipairs(lines) do
    line_keys[line_idx] = line_render_key(line, highlights[line_idx] or {}, preview_lines[line_idx])
  end

  local old_keys = s.render_keys or {}
  local start_idx, old_end, new_end = diff_range(old_keys, line_keys)
  if start_idx then
    local replace = slice_lines(lines, start_idx, new_end)

    vim.bo[s.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(s.bufnr, start_idx - 1, old_end, false, replace)
    vim.bo[s.bufnr].modifiable = false

    vim.api.nvim_buf_clear_namespace(s.bufnr, NS, start_idx - 1, old_end)
    apply_highlights_in_range(s.bufnr, highlights, preview_lines, start_idx, new_end)
  end
  s.render_keys = line_keys

  if s.winid and vim.api.nvim_win_is_valid(s.winid) and s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) then
    local line_count = vim.api.nvim_buf_line_count(s.bufnr)
    if line_count > s.header_lines then
      local min_line = s.header_lines + 1
      local cursor = vim.api.nvim_win_get_cursor(s.winid)[1]
      if cursor < min_line then
        vim.api.nvim_win_set_cursor(s.winid, { min_line, 0 })
      end
    end
  end
end

return M
