local config = require("peekstack.config")
local layout = require("peekstack.core.layout")
local fs = require("peekstack.util.fs")
local str = require("peekstack.util.str")
local treesitter = require("peekstack.util.treesitter")

local M = {}

---Get treesitter context for a location if enabled
---@param location PeekstackLocation
---@param ui_config table
---@return string
local function get_treesitter_context(location, ui_config)
  local context_cfg = ui_config.title.context
  if not context_cfg or not context_cfg.enabled then
    return ""
  end

  local fname = fs.uri_to_fname(location.uri)
  local bufnr = vim.fn.bufnr(fname)
  if not bufnr or bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    return ""
  end

  local ctx =
    treesitter.context_at(bufnr, location.range.start.line or 0, location.range.start.character or 0, context_cfg)

  if not ctx or ctx == "" then
    return ""
  end

  local separator = context_cfg.separator or " • "
  return separator .. ctx
end

---@type table<integer, string>
local severity_labels = {
  [1] = "[Error] ",
  [2] = "[Warn] ",
  [3] = "[Info] ",
  [4] = "[Hint] ",
}

---@type table<integer, string>
local severity_hl_groups = {
  [1] = "PeekstackTitleKindError",
  [2] = "PeekstackTitleKindWarn",
  [3] = "PeekstackTitleKindInfo",
  [4] = "PeekstackTitleKindHint",
}

---@param chunks PeekstackTitleChunk[]
---@param text string
---@param hl_group? string
local function push_chunk(chunks, text, hl_group)
  if text == "" then
    return
  end
  local last = chunks[#chunks]
  if last and last[2] == hl_group then
    last[1] = last[1] .. text
    return
  end
  if hl_group then
    table.insert(chunks, { text, hl_group })
  else
    table.insert(chunks, { text })
  end
end

---@param fmt string
---@param data table<string, string>
---@param hls table<string, string?>
---@return PeekstackTitleChunk[]
local function format_title_chunks(fmt, data, hls)
  local chunks = {}
  if fmt == "" then
    return chunks
  end
  local idx = 1
  while idx <= #fmt do
    local start_idx, end_idx, key = fmt:find("{(.-)}", idx)
    if not start_idx then
      local last = chunks[#chunks]
      push_chunk(chunks, fmt:sub(idx), last and last[2])
      break
    end
    if start_idx > idx then
      local last = chunks[#chunks]
      push_chunk(chunks, fmt:sub(idx, start_idx - 1), last and last[2])
    end
    local val = data[key]
    if val and val ~= "" then
      push_chunk(chunks, tostring(val), hls[key])
    end
    idx = end_idx + 1
  end
  return chunks
end

---Build the title string for a popup window
---@param location PeekstackLocation
---@return PeekstackTitleChunk[]?
function M.build_title(location)
  local ui = config.get().ui
  if not ui.title.enabled then
    return nil
  end

  local provider_name = location.provider or ""
  local is_diagnostic = provider_name:match("^diagnostics%.") ~= nil

  local icon = ""
  local icons_cfg = ui.title.icons
  if type(icons_cfg) == "table" and icons_cfg.enabled and type(icons_cfg.map) == "table" then
    local category = provider_name:match("^(.-)%.") or provider_name
    icon = icons_cfg.map[provider_name] or icons_cfg.map[category] or ""
  end

  local ui_path = ui.path or {}
  local raw_path = fs.uri_to_fname(location.uri)
  local path
  if ui_path.base then
    path = str.relative_path(raw_path, ui_path.base)
  else
    path = str.shorten_path(raw_path)
  end
  local path_max_width = ui_path.max_width
  if type(path_max_width) == "number" and path_max_width > 0 then
    path = str.truncate_middle(path, path_max_width)
  end
  local line = (location.range.start.line or 0) + 1
  local context = get_treesitter_context(location, ui)

  local kind = ""
  local kind_hl = nil
  if type(location.kind) == "number" then
    kind = severity_labels[location.kind] or ""
    kind_hl = severity_hl_groups[location.kind]
  end

  local text = location.text or ""
  if text ~= "" then
    text = text:gsub("%s+", " ")
    text = vim.trim(text)
  end

  local provider = provider_name
  local format = ui.title.format or ""
  if type(format) ~= "string" then
    format = ""
  end
  if is_diagnostic and text ~= "" then
    if not format:find("{text}", 1, true) then
      provider = text
    end
  end

  local data = {
    icon = icon,
    provider = provider,
    path = path,
    line = tostring(line),
    context = context,
    kind = kind,
    text = text,
  }

  local hls = {
    icon = "PeekstackTitleIcon",
    provider = "PeekstackTitleProvider",
    path = "PeekstackTitlePath",
    line = "PeekstackTitleLine",
    text = nil,
    kind = kind_hl,
  }

  local chunks = format_title_chunks(format, data, hls)
  if #chunks == 0 then
    return nil
  end
  return chunks
end

---@param title string|PeekstackTitleChunk[]|nil
---@return string
function M.title_text(title)
  if not title then
    return ""
  end
  if type(title) == "string" then
    return title
  end
  if type(title) ~= "table" then
    return ""
  end
  local parts = {}
  for _, chunk in ipairs(title) do
    if type(chunk) == "table" then
      table.insert(parts, tostring(chunk[1] or ""))
    elseif type(chunk) == "string" then
      table.insert(parts, chunk)
    end
  end
  return table.concat(parts)
end

---Take count characters starting at character start out of chunks, keeping
---each piece's highlight group.
---@param chunks PeekstackTitleChunk[]
---@param start integer
---@param count integer
---@return PeekstackTitleChunk[]
local function slice_chunks(chunks, start, count)
  local result = {}
  local offset = 0
  for _, c in ipairs(chunks) do
    local text = c[1] or ""
    local chars = vim.fn.strchars(text, true)
    local from = math.max(start - offset, 0)
    local to = math.min(start + count - offset, chars)
    if to > from then
      local piece = vim.fn.strcharpart(text, from, to - from, true)
      table.insert(result, c[2] and { piece, c[2] } or { piece })
    end
    offset = offset + chars
  end
  return result
end

---Truncate structured title chunks using the same middle-ellipsis strategy
---as str.truncate_middle, preserving highlight groups on the kept portions.
---@param chunks PeekstackTitleChunk[]
---@param max_width integer
---@return PeekstackTitleChunk[]
function M.truncate_chunks(chunks, max_width)
  if not chunks or #chunks == 0 or max_width <= 0 then
    return chunks or {}
  end

  local texts = {}
  for _, c in ipairs(chunks) do
    table.insert(texts, c[1] or "")
  end
  local text = table.concat(texts)
  if vim.fn.strdisplaywidth(text) <= max_width then
    return chunks
  end

  local ellipsis = "..."
  local ew = vim.fn.strdisplaywidth(ellipsis)
  if max_width <= ew then
    return { { ellipsis:sub(1, max_width) } }
  end

  -- Cut the joined text like truncate_middle, then map both kept ends back
  -- onto the chunks they came from.
  local remaining = max_width - ew
  local left_text, left_width = str.take_width(text, math.ceil(remaining / 2))
  local right_text = str.take_width_right(text, remaining - left_width, left_width + ew)
  local total_chars = vim.fn.strchars(text, true)
  local right_chars = vim.fn.strchars(right_text, true)

  local result = slice_chunks(chunks, 0, vim.fn.strchars(left_text, true))
  table.insert(result, { ellipsis })
  vim.list_extend(result, slice_chunks(chunks, total_chars - right_chars, right_chars))
  return result
end

---Open a popup window for a location
---@param bufnr integer
---@param location PeekstackLocation
---@param opts? { buffer_mode?: "copy"|"source" }
---@return integer winid
---@return PeekstackRenderWinOpts win_opts
function M.open(bufnr, location, opts)
  local layout_opts = layout.compute(1)
  ---@type PeekstackRenderWinOpts
  local win_opts = {
    relative = "editor",
    row = layout_opts.row,
    col = layout_opts.col,
    width = layout_opts.width,
    height = layout_opts.height,
    style = "minimal",
    border = "rounded",
    focusable = true,
    zindex = layout_opts.zindex,
  }

  local title = M.build_title(location)
  if title then
    win_opts.title = title
    win_opts.title_pos = "center"
  end

  local winid = vim.api.nvim_open_win(bufnr, true, win_opts)
  vim.wo[winid].winhighlight = "FloatBorder:PeekstackPopupBorderFocused"
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = true
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].foldcolumn = "0"
  vim.wo[winid].spell = false
  vim.wo[winid].list = false
  if not opts or opts.buffer_mode ~= "source" then
    vim.bo[bufnr].buflisted = false
  end

  return winid, win_opts
end

return M
