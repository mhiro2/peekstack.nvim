local M = {}

local NS = vim.api.nvim_create_namespace("PeekstackStackView")
local TS_HL_PRIORITY = 150

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

---@param preview PeekstackStackViewPreviewLine
---@param parser_cache table<integer, PeekstackStackViewParserCacheEntry|false>
---@return PeekstackStackViewPreviewTsHighlight[]?
local function collect_preview_treesitter_highlights(preview, parser_cache)
  local source_bufnr = preview.source_bufnr
  if not source_bufnr or not vim.api.nvim_buf_is_valid(source_bufnr) then
    return nil
  end

  local source_line = preview.source_line
  local source_start = preview.source_col_start
  local source_end = preview.source_col_end
  if source_end <= source_start then
    return nil
  end

  local parser_entry = get_parser_cache_entry(parser_cache, source_bufnr)
  if not parser_entry then
    return nil
  end

  local root, lang = treesitter_root_for_line(parser_entry, source_line)
  if not root or not lang then
    return nil
  end

  local query = get_treesitter_highlight_query(lang)
  if not query then
    return nil
  end

  ---@type PeekstackStackViewPreviewTsHighlight[]
  local highlights = {}
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
            table.insert(highlights, {
              start_offset = start_col - source_start,
              end_offset = end_col - source_start,
              hl_group = hl_group,
            })
          end
        end
      end
    end
  end)

  if not ok_iter or #highlights == 0 then
    return nil
  end

  return highlights
end

---@param preview PeekstackStackViewPreviewLine
---@return string?
local function cache_key(preview)
  local source_bufnr = preview.source_bufnr
  if not source_bufnr or not vim.api.nvim_buf_is_valid(source_bufnr) then
    return nil
  end

  local changedtick = vim.api.nvim_buf_get_changedtick(source_bufnr)
  return string.format(
    "%d:%d:%d:%d:%d",
    source_bufnr,
    changedtick,
    preview.source_line,
    preview.source_col_start,
    preview.source_col_end
  )
end

---@param target_bufnr integer
---@param preview_line_nr integer
---@param preview PeekstackStackViewPreviewLine
---@param highlights PeekstackStackViewPreviewTsHighlight[]
local function apply_cached_highlights(target_bufnr, preview_line_nr, preview, highlights)
  for _, hl in ipairs(highlights) do
    local view_start = preview.preview_col_start + hl.start_offset
    local view_end = preview.preview_col_start + hl.end_offset
    vim.api.nvim_buf_set_extmark(target_bufnr, NS, preview_line_nr - 1, view_start, {
      end_col = view_end,
      hl_group = hl.hl_group,
      priority = TS_HL_PRIORITY,
    })
  end
end

---Get a trimmed preview line from a source buffer.
---@param source_bufnr integer?
---@param line integer
---@param max_width integer
---@param preview_prefix string
---@return PeekstackStackViewPreviewLine?
function M.preview_line(source_bufnr, line, max_width, preview_prefix)
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

---@param target_bufnr integer
---@param previews table<integer, PeekstackStackViewPreviewLine>
---@param preview_cache table<string, PeekstackStackViewPreviewTsHighlight[]|false>
function M.apply_treesitter_highlights(target_bufnr, previews, preview_cache)
  ---@type table<integer, PeekstackStackViewParserCacheEntry|false>
  local parser_cache = {}

  for preview_line_nr, preview in pairs(previews) do
    local preview_cache_key = cache_key(preview)
    local cached = preview_cache_key and preview_cache[preview_cache_key] or nil
    if cached == nil then
      local computed = collect_preview_treesitter_highlights(preview, parser_cache)
      if preview_cache_key then
        preview_cache[preview_cache_key] = computed or false
      end
      cached = computed
    end
    if cached and cached ~= false then
      apply_cached_highlights(target_bufnr, preview_line_nr, preview, cached)
    end
  end
end

return M
