local config = require("peekstack.config")
local location = require("peekstack.core.location")
local render_mod = require("peekstack.ui.render")
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

---@class PeekstackStackViewState
---@field bufnr integer?
---@field winid integer?
---@field root_winid integer?
---@field line_to_id table<integer, integer>
---@field filter string?
---@field header_lines integer
---@field help_bufnr integer?
---@field help_winid integer?
---@field help_augroup integer?
---@field autoclose_group integer?
---@field autoclose_suspended integer

---@type table<integer, PeekstackStackViewState>
local states = {}

---@param s PeekstackStackViewState
local function cleanup_state(s)
  if s.help_winid and vim.api.nvim_win_is_valid(s.help_winid) then
    pcall(vim.api.nvim_win_close, s.help_winid, true)
  end
  s.help_winid = nil
  s.help_bufnr = nil
  if s.help_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, s.help_augroup)
    s.help_augroup = nil
  end
  if s.autoclose_group then
    pcall(vim.api.nvim_del_augroup_by_id, s.autoclose_group)
    s.autoclose_group = nil
  end
end

local function cleanup_invalid_states()
  for tabpage, s in pairs(states) do
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      cleanup_state(s)
      states[tabpage] = nil
    end
  end
end

do
  local group = vim.api.nvim_create_augroup("PeekstackStackViewTabCleanup", { clear = true })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      cleanup_invalid_states()
    end,
  })
end

---@return PeekstackStackViewState
local function get_state()
  local tabpage = vim.api.nvim_get_current_tabpage()
  if not states[tabpage] then
    states[tabpage] = {
      bufnr = nil,
      winid = nil,
      root_winid = nil,
      line_to_id = {},
      filter = nil,
      header_lines = 0,
      help_bufnr = nil,
      help_winid = nil,
      help_augroup = nil,
      autoclose_group = nil,
      autoclose_suspended = 0,
    }
  end
  return states[tabpage]
end

---@param s PeekstackStackViewState
---@return boolean
local function is_open(s)
  return s.winid ~= nil and vim.api.nvim_win_is_valid(s.winid)
end

---@param s table
---@return boolean
local function is_ready(s)
  return s.bufnr ~= nil and s.winid ~= nil and vim.api.nvim_buf_is_valid(s.bufnr) and vim.api.nvim_win_is_valid(s.winid)
end

---@param s table
local function focus_stack_view(s)
  if s.winid and vim.api.nvim_win_is_valid(s.winid) then
    vim.api.nvim_set_current_win(s.winid)
  end
end

---@param s table
local function suspend_autoclose(s)
  s.autoclose_suspended = (s.autoclose_suspended or 0) + 1
end

---@param s table
local function resume_autoclose(s)
  if s.autoclose_suspended then
    s.autoclose_suspended = math.max(s.autoclose_suspended - 1, 0)
  end
end

---@param s table
local function focus_root_win(s)
  if s.root_winid and vim.api.nvim_win_is_valid(s.root_winid) then
    vim.api.nvim_set_current_win(s.root_winid)
  end
end

---@param s table
local function refocus_and_resume(s)
  focus_stack_view(s)
  resume_autoclose(s)
end

---@param s PeekstackStackViewState
---@return boolean
local function should_autoclose(s)
  if s.autoclose_suspended and s.autoclose_suspended > 0 then
    return false
  end
  if not is_open(s) then
    return false
  end
  local current = vim.api.nvim_get_current_win()
  if s.winid and current == s.winid then
    return false
  end
  if s.help_winid and vim.api.nvim_win_is_valid(s.help_winid) and current == s.help_winid then
    return false
  end
  return true
end

---@param s table
---@param opts? { refocus: boolean }
local function close_help(s, opts)
  local had_help = s.help_winid and vim.api.nvim_win_is_valid(s.help_winid)
  local refocus = true
  if opts and opts.refocus == false then
    refocus = false
  end
  if had_help then
    vim.api.nvim_win_close(s.help_winid, true)
  end
  s.help_winid = nil
  s.help_bufnr = nil
  if s.help_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, s.help_augroup)
    s.help_augroup = nil
  end
  if had_help then
    if refocus then
      focus_stack_view(s)
    end
    resume_autoclose(s)
  end
end

---@param label string
---@param filter? string
---@return boolean
local function matches_filter(label, filter)
  if not filter or filter == "" then
    return true
  end
  return label:lower():find(filter:lower(), 1, true) ~= nil
end

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
---@param line integer
---@return TSNode?, string?
local function treesitter_root_for_line(bufnr, line)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return nil, nil
  end
  local ok_parse = pcall(function()
    parser:parse()
  end)
  if not ok_parse then
    return nil, nil
  end
  local trees = parser:trees()
  if not trees or vim.tbl_isempty(trees) then
    return nil, nil
  end

  local root = nil
  local lang = nil
  local smallest_range = math.huge
  for _, tree in pairs(trees) do
    local candidate = tree:root()
    if candidate then
      local sr, _, er, _ = candidate:range()
      if line >= sr and line <= er then
        local range_size = er - sr
        if range_size < smallest_range then
          smallest_range = range_size
          root = candidate
          local ok_lang, tree_lang = pcall(function()
            return tree:lang()
          end)
          if ok_lang and type(tree_lang) == "string" and tree_lang ~= "" then
            lang = tree_lang
          else
            lang = nil
          end
        end
      end
    end
  end
  if not root then
    return nil, nil
  end
  if not lang then
    local ft = vim.bo[bufnr].filetype
    if ft ~= "" then
      local ok_map, mapped = pcall(vim.treesitter.language.get_lang, ft)
      if ok_map and type(mapped) == "string" and mapped ~= "" then
        lang = mapped
      else
        lang = ft
      end
    end
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
local function apply_preview_treesitter_highlight(target_bufnr, preview_line_nr, preview)
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

  local root, lang = treesitter_root_for_line(source_bufnr, source_line)
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
  for preview_line_nr, preview in pairs(previews) do
    apply_preview_treesitter_highlight(target_bufnr, preview_line_nr, preview)
  end
end

--- Get a trimmed preview line from a source buffer
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

---Sort visible items in DFS tree order so children appear right after their parent.
---Items without a visible parent are treated as roots and keep their relative order.
---@param items PeekstackPopupModel[]
---@return PeekstackPopupModel[]
local function tree_sort(items)
  local by_id = {}
  for _, popup in ipairs(items) do
    by_id[popup.id] = popup
  end

  ---@type table<integer, PeekstackPopupModel[]>
  local children = {}
  local roots = {}

  for _, popup in ipairs(items) do
    local pid = popup.parent_popup_id
    if pid and by_id[pid] then
      if not children[pid] then
        children[pid] = {}
      end
      table.insert(children[pid], popup)
    else
      table.insert(roots, popup)
    end
  end

  local result = {}
  local visiting = {}
  local function dfs(node)
    if visiting[node.id] then
      return
    end
    visiting[node.id] = true
    table.insert(result, node)
    if children[node.id] then
      for _, child in ipairs(children[node.id]) do
        dfs(child)
      end
    end
  end

  for _, root in ipairs(roots) do
    dfs(root)
  end

  -- Safety fallback: keep any unvisited items (e.g. cyclic/invalid parent links)
  -- so entries are never dropped from the stack view.
  for _, popup in ipairs(items) do
    if not visiting[popup.id] then
      dfs(popup)
    end
  end

  return result
end

---@param items PeekstackPopupModel[]
---@return table<integer, PeekstackPopupModel>
local function visible_popup_by_id(items)
  local by_id = {}
  for _, popup in ipairs(items) do
    by_id[popup.id] = popup
  end
  return by_id
end

---@param visible PeekstackPopupModel[]
---@return table<integer, string>
local function tree_guide_by_id(visible)
  local guides = {}
  local by_id = visible_popup_by_id(visible)
  ---@type table<integer, integer[]>
  local children_by_parent = {}

  -- Children order follows `visible` (stack push order).
  -- If sorting is added, children_by_parent must be rebuilt in display order.
  for _, popup in ipairs(visible) do
    local parent_id = popup.parent_popup_id
    if parent_id and by_id[parent_id] then
      if not children_by_parent[parent_id] then
        children_by_parent[parent_id] = {}
      end
      table.insert(children_by_parent[parent_id], popup.id)
    end
  end

  ---@type table<integer, integer>
  local sibling_pos = {}
  ---@type table<integer, integer>
  local sibling_total = {}
  for _, children in pairs(children_by_parent) do
    local total = #children
    for idx, child_id in ipairs(children) do
      sibling_pos[child_id] = idx
      sibling_total[child_id] = total
    end
  end

  ---@type table<integer, integer[]>
  local chain_cache = {}

  ---@param popup_id integer
  ---@param visiting table<integer, boolean>
  ---@return integer[]
  local function visible_chain(popup_id, visiting)
    local cached = chain_cache[popup_id]
    if cached then
      return cached
    end
    if visiting[popup_id] then
      return {}
    end

    local popup = by_id[popup_id]
    if not popup then
      return {}
    end

    local parent_id = popup.parent_popup_id
    if not parent_id or not by_id[parent_id] then
      local root_chain = { popup_id }
      chain_cache[popup_id] = root_chain
      return root_chain
    end

    visiting[popup_id] = true
    local parent_chain = visible_chain(parent_id, visiting)
    visiting[popup_id] = nil

    local chain = {}
    for _, id in ipairs(parent_chain) do
      table.insert(chain, id)
    end
    table.insert(chain, popup_id)
    chain_cache[popup_id] = chain
    return chain
  end

  for _, popup in ipairs(visible) do
    local chain = visible_chain(popup.id, {})
    local depth = #chain - 1
    if depth > 0 then
      local segments = {}
      for level = 1, depth - 1 do
        local path_child_id = chain[level + 1]
        local pos = sibling_pos[path_child_id] or 1
        local total = sibling_total[path_child_id] or 1
        segments[#segments + 1] = (pos < total) and "│ " or "  "
      end
      local pos = sibling_pos[popup.id] or 1
      local total = sibling_total[popup.id] or 1
      segments[#segments + 1] = (pos < total) and "├ " or "└ "
      guides[popup.id] = table.concat(segments)
    else
      guides[popup.id] = ""
    end
  end
  return guides
end

---Render the stack view list
---@param s table
local function render(s)
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
  local lines = {}
  ---@type PeekstackStackViewHighlight[][]
  local highlights = {}
  ---@type table<integer, PeekstackStackViewPreviewLine>
  local preview_lines = {}
  s.line_to_id = {}
  s.header_lines = 0

  local visible = {}
  for _, popup in ipairs(items) do
    local filter_label = popup.title
      or location.display_text(popup.location, 0, {
        path_base = ui_path.base,
      })
    if matches_filter(filter_label, s.filter) then
      table.insert(visible, popup)
    end
  end
  visible = tree_sort(visible)
  local tree_guides = tree_guide_by_id(visible)

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
    local label
    local label_chunks
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
    local line_hls = {}
    -- Focus marker highlight
    if is_focused then
      table.insert(line_hls, { col_start = 0, col_end = #focus_marker, hl_group = "PeekstackStackViewFocused" })
    end
    -- Index number highlight
    local idx_start = #focus_marker
    table.insert(
      line_hls,
      { col_start = idx_start, col_end = idx_start + #index_str, hl_group = "PeekstackStackViewIndex" }
    )
    -- Pinned badge highlight
    if popup.pinned then
      local pin_start = idx_start + #index_str
      table.insert(line_hls, {
        col_start = pin_start,
        col_end = pin_start + #pinned,
        hl_group = "PeekstackStackViewPinned",
      })
    end
    if tree_guide ~= "" then
      -- Byte offsets: #tree_guide is byte length, correct for extmark col/end_col.
      local tree_start = idx_start + #index_str + #pinned
      table.insert(line_hls, {
        col_start = tree_start,
        col_end = tree_start + #tree_guide,
        hl_group = "PeekstackStackViewTree",
      })
    end
    -- Label highlighting from structured title chunks
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

    -- Preview line
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

  vim.bo[s.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(s.bufnr, 0, -1, false, lines)
  vim.bo[s.bufnr].modifiable = false

  vim.api.nvim_buf_clear_namespace(s.bufnr, NS, 0, -1)
  for line_idx, line_hls in ipairs(highlights) do
    for _, hl in ipairs(line_hls) do
      local opts = {
        end_col = hl.col_end,
        hl_group = hl.hl_group,
      }
      if hl.hl_group == "PeekstackStackViewPreview" then
        opts.priority = PREVIEW_BASE_HL_PRIORITY
      end
      vim.api.nvim_buf_set_extmark(s.bufnr, NS, line_idx - 1, hl.col_start, {
        end_col = opts.end_col,
        hl_group = opts.hl_group,
        priority = opts.priority,
      })
    end
  end
  apply_preview_treesitter_highlights(s.bufnr, preview_lines)

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

---@param s table
---@param s table
---@return integer[]
local function entry_lines(s)
  local id_to_line = {}
  for line, id in pairs(s.line_to_id or {}) do
    if line > (s.header_lines or 0) and (not id_to_line[id] or line < id_to_line[id]) then
      id_to_line[id] = line
    end
  end
  local lines = {}
  for _, line in pairs(id_to_line) do
    table.insert(lines, line)
  end
  table.sort(lines)
  return lines
end

---@param s table
local function ensure_non_header_cursor(s)
  if not (s.winid and vim.api.nvim_win_is_valid(s.winid) and s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr)) then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(s.bufnr)
  if line_count <= 0 then
    return
  end
  local min_line = math.min((s.header_lines or 0) + 1, line_count)
  local cursor = vim.api.nvim_win_get_cursor(s.winid)[1]
  if cursor < min_line then
    vim.api.nvim_win_set_cursor(s.winid, { min_line, 0 })
  end
end

---@param s table
---@param step integer
local function move_cursor_by_stack_item(s, step)
  if not (s.winid and vim.api.nvim_win_is_valid(s.winid)) then
    return
  end
  local lines = entry_lines(s)
  if #lines == 0 then
    ensure_non_header_cursor(s)
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(s.winid)[1]
  if cursor_line <= (s.header_lines or 0) then
    vim.api.nvim_win_set_cursor(s.winid, { lines[1], 0 })
    return
  end

  local current_id = s.line_to_id[cursor_line]
  local base_line = cursor_line
  if current_id then
    for line, id in pairs(s.line_to_id) do
      if id == current_id and line < base_line then
        base_line = line
      end
    end
  end

  local target_line = base_line
  if step > 0 then
    for _, line in ipairs(lines) do
      if line > base_line then
        target_line = line
        break
      end
    end
  else
    for idx = #lines, 1, -1 do
      local line = lines[idx]
      if line < base_line then
        target_line = line
        break
      end
    end
  end

  vim.api.nvim_win_set_cursor(s.winid, { target_line, 0 })
end

---@param s table
local function toggle_help(s)
  if s.help_winid and vim.api.nvim_win_is_valid(s.help_winid) then
    close_help(s)
    return
  end
  suspend_autoclose(s)
  local lines = {
    "Peekstack Stack View",
    "",
    "<CR>  Focus selected popup",
    "dd    Close selected popup",
    "u     Undo close (restore last)",
    "U     Restore all closed popups",
    "H     History list (select to restore)",
    "r     Rename selected popup",
    "p     Toggle pin (skip auto-close)",
    "/     Filter list",
    "gg/G  Jump to first/last stack item",
    "j/k   Move cursor by stack item",
    "q     Close stack view",
    "?     Toggle this help",
  }
  s.help_bufnr = vim.api.nvim_create_buf(false, true)
  local fs = require("peekstack.util.fs")
  fs.configure_buffer(s.help_bufnr)
  vim.bo[s.help_bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(s.help_bufnr, 0, -1, false, lines)
  vim.bo[s.help_bufnr].modifiable = false
  vim.bo[s.help_bufnr].filetype = "peekstack-stack-help"

  local win_width = vim.api.nvim_win_get_width(s.winid)
  local win_height = vim.api.nvim_win_get_height(s.winid)
  local max_len = 0
  for _, line in ipairs(lines) do
    if #line > max_len then
      max_len = #line
    end
  end
  local width = math.min(max_len + 2, math.max(20, win_width - 4))
  local height = math.min(#lines, math.max(4, win_height - 4))
  local row = math.max(1, math.floor((win_height - height) / 2))
  local col = math.max(1, math.floor((win_width - width) / 2))
  local parent_cfg = vim.api.nvim_win_get_config(s.winid)
  local base_z = 100
  if type(parent_cfg.zindex) == "number" then
    base_z = parent_cfg.zindex
  end
  s.help_winid = vim.api.nvim_open_win(s.help_bufnr, true, {
    relative = "win",
    win = s.winid,
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = true,
    zindex = base_z + 1,
  })
  local help_group =
    vim.api.nvim_create_augroup(string.format("PeekstackStackViewHelp_%d", vim.api.nvim_get_current_tabpage()), {
      clear = true,
    })
  s.help_augroup = help_group
  vim.api.nvim_create_autocmd("WinLeave", {
    group = help_group,
    buffer = s.help_bufnr,
    callback = function()
      vim.schedule(function()
        if not (s.help_winid and vim.api.nvim_win_is_valid(s.help_winid)) then
          return
        end
        close_help(s, { refocus = false })
        if is_open(s) and vim.api.nvim_get_current_win() ~= s.winid then
          M.toggle()
        end
      end)
    end,
  })
  vim.keymap.set("n", "q", function()
    close_help(s)
  end, { buffer = s.help_bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    close_help(s)
  end, { buffer = s.help_bufnr, nowait = true, silent = true })
  vim.keymap.set("n", "?", function()
    close_help(s)
  end, { buffer = s.help_bufnr, nowait = true, silent = true })
end

---@param s table
local function apply_keymaps(s)
  vim.keymap.set("n", "<CR>", function()
    local line = vim.api.nvim_win_get_cursor(s.winid)[1]
    local id = s.line_to_id[line]
    if id then
      local stack = require("peekstack.core.stack")
      stack.focus_by_id(id, s.root_winid)
    end
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "dd", function()
    local line = vim.api.nvim_win_get_cursor(s.winid)[1]
    local id = s.line_to_id[line]
    if id then
      local stack = require("peekstack.core.stack")
      stack.close_by_id(id, s.root_winid)
      render(s)
    end
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "u", function()
    suspend_autoclose(s)
    local stack = require("peekstack.core.stack")
    focus_root_win(s)
    local restored = stack.restore_last(s.root_winid)
    if restored then
      render(s)
    else
      if #stack.history_list(s.root_winid) > 0 then
        vim.notify("Failed to restore popup", vim.log.levels.WARN)
      else
        vim.notify("No closed popups to restore", vim.log.levels.INFO)
      end
    end
    refocus_and_resume(s)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "r", function()
    local line = vim.api.nvim_win_get_cursor(s.winid)[1]
    local id = s.line_to_id[line]
    if not id then
      return
    end
    suspend_autoclose(s)
    vim.ui.input({ prompt = "Rename" }, function(input)
      if not input or input == "" then
        refocus_and_resume(s)
        return
      end
      local stack = require("peekstack.core.stack")
      stack.rename_by_id(id, input, s.root_winid)
      render(s)
      refocus_and_resume(s)
    end)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "p", function()
    local line = vim.api.nvim_win_get_cursor(s.winid)[1]
    local id = s.line_to_id[line]
    if not id then
      return
    end
    local stack = require("peekstack.core.stack")
    stack.toggle_pin_by_id(id, s.root_winid)
    render(s)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "/", function()
    suspend_autoclose(s)
    vim.ui.input({ prompt = "Filter" }, function(input)
      if input == nil then
        refocus_and_resume(s)
        return
      end
      if input == "" then
        s.filter = nil
      else
        s.filter = input
      end
      render(s)
      refocus_and_resume(s)
    end)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "gg", function()
    local lines = entry_lines(s)
    if #lines == 0 then
      ensure_non_header_cursor(s)
      return
    end
    vim.api.nvim_win_set_cursor(s.winid, { lines[1], 0 })
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "G", function()
    local lines = entry_lines(s)
    if #lines == 0 then
      ensure_non_header_cursor(s)
      return
    end
    vim.api.nvim_win_set_cursor(s.winid, { lines[#lines], 0 })
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "j", function()
    local count = vim.v.count1
    for _ = 1, count do
      move_cursor_by_stack_item(s, 1)
    end
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "k", function()
    local count = vim.v.count1
    for _ = 1, count do
      move_cursor_by_stack_item(s, -1)
    end
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "U", function()
    suspend_autoclose(s)
    local stack = require("peekstack.core.stack")
    focus_root_win(s)
    local restored = stack.restore_all(s.root_winid)
    if #restored > 0 then
      render(s)
    end
    local remaining = stack.history_list(s.root_winid)
    if #remaining > 0 then
      vim.notify("Some popups could not be restored", vim.log.levels.WARN)
    elseif #restored == 0 then
      vim.notify("No closed popups to restore", vim.log.levels.INFO)
    end
    refocus_and_resume(s)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "H", function()
    local stack = require("peekstack.core.stack")
    local history = stack.history_list(s.root_winid)
    if #history == 0 then
      vim.notify("No history entries", vim.log.levels.INFO)
      return
    end
    suspend_autoclose(s)
    local ui_path = config.get().ui.path or {}
    local max_width = ui_path.max_width or 0
    if max_width == 0 then
      max_width = math.floor(vim.o.columns * 0.7)
    end
    local items = {}
    for i = #history, 1, -1 do
      local entry = history[i]
      local label = entry.title and str.truncate_middle(entry.title, max_width)
        or location.display_text(entry.location, 0, {
          path_base = ui_path.base,
          max_width = max_width,
        })
      table.insert(items, { idx = i, label = label, entry = entry })
    end
    vim.ui.select(items, {
      prompt = "History",
      format_item = function(item)
        return item.label
      end,
    }, function(selected, idx)
      if selected or idx then
        local restore_idx = nil
        if type(selected) == "table" and selected.idx then
          restore_idx = selected.idx
        elseif type(idx) == "number" and items[idx] then
          restore_idx = items[idx].idx
        elseif type(selected) == "string" then
          for _, item in ipairs(items) do
            if item.label == selected then
              restore_idx = item.idx
              break
            end
          end
        end
        if restore_idx then
          focus_root_win(s)
          local restored = stack.restore_from_history(restore_idx, s.root_winid)
          if restored then
            render(s)
          else
            vim.notify("Failed to restore history entry", vim.log.levels.WARN)
          end
        else
          vim.notify("Failed to restore history entry", vim.log.levels.WARN)
        end
      end
      refocus_and_resume(s)
      if not selected then
        return
      end
    end)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "?", function()
    toggle_help(s)
  end, { buffer = s.bufnr, nowait = true, silent = true })

  vim.keymap.set("n", "q", function()
    M.toggle()
  end, { buffer = s.bufnr, nowait = true, silent = true })
end

---Find a non-floating window to use as root.
---@return integer
local function find_root_winid()
  local winid = vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(winid)
  if cfg.relative == "" then
    return winid
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local c = vim.api.nvim_win_get_config(w)
    if c.relative == "" then
      return w
    end
  end
  return winid
end

---Compute floating window config for the stack view (right-side panel).
---@return table
local function stack_view_win_config()
  local columns = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight
  local width = math.max(30, math.floor(columns * 0.3))
  local height = math.max(6, lines - 2)
  return {
    relative = "editor",
    row = 0,
    col = columns - width,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = true,
    zindex = 100,
    title = "Stack View",
    title_pos = "center",
  }
end

---Open the stack view
function M.open()
  local s = get_state()
  if is_open(s) then
    vim.api.nvim_set_current_win(s.winid)
    render(s)
    return
  end

  s.autoclose_suspended = 0
  s.root_winid = find_root_winid()
  s.bufnr = vim.api.nvim_create_buf(false, true)
  s.winid = vim.api.nvim_open_win(s.bufnr, true, stack_view_win_config())
  vim.wo[s.winid].cursorline = true
  vim.wo[s.winid].winhighlight = "CursorLine:PeekstackStackViewCursorLine"
  vim.api.nvim_win_set_var(s.winid, "peekstack_root_winid", s.root_winid)
  require("peekstack.core.stack")._register_stack_view_win(s.winid)

  local fs = require("peekstack.util.fs")
  fs.configure_buffer(s.bufnr)
  vim.bo[s.bufnr].modifiable = false
  vim.bo[s.bufnr].filetype = "peekstack-stack"

  -- Auto-close when focus leaves the stack view window
  local group_name = string.format("PeekstackStackViewAutoClose:%d", s.bufnr)
  local au_group = vim.api.nvim_create_augroup(group_name, { clear = true })
  s.autoclose_group = au_group
  vim.api.nvim_create_autocmd("WinLeave", {
    group = au_group,
    buffer = s.bufnr,
    callback = function()
      vim.schedule(function()
        if not should_autoclose(s) then
          return
        end
        close_help(s)
        vim.api.nvim_win_close(s.winid, true)
        s.winid = nil
        s.bufnr = nil
        s.root_winid = nil
        s.autoclose_suspended = 0
        s.help_augroup = nil
        if s.autoclose_group then
          pcall(vim.api.nvim_del_augroup_by_id, s.autoclose_group)
        end
        s.autoclose_group = nil
      end)
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = au_group,
    buffer = s.bufnr,
    callback = function()
      ensure_non_header_cursor(s)
    end,
  })

  apply_keymaps(s)
  render(s)
end

---Toggle the stack view (open if closed, close if open)
function M.toggle()
  local s = get_state()
  if is_open(s) then
    close_help(s)
    if s.autoclose_group then
      pcall(vim.api.nvim_del_augroup_by_id, s.autoclose_group)
    end
    s.autoclose_group = nil
    vim.api.nvim_win_close(s.winid, true)
    s.winid = nil
    s.bufnr = nil
    s.root_winid = nil
    s.autoclose_suspended = 0
    s.help_augroup = nil
    return
  end
  M.open()
end

---Re-render all open stack views (called on push/close events).
function M.refresh_all()
  for _, s in pairs(states) do
    if is_open(s) and s.bufnr and vim.api.nvim_buf_is_valid(s.bufnr) then
      render(s)
    end
  end
end

---Get stack view state (for testing).
---@return table
function M._get_state()
  return get_state()
end

---Get stack view state count (for testing).
---@return integer
function M._state_count()
  local count = 0
  for _ in pairs(states) do
    count = count + 1
  end
  return count
end

---Render stack view state (for testing).
---@param s table
function M._render(s)
  render(s)
end

return M
