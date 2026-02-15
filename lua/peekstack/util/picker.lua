local config = require("peekstack.config")
local location = require("peekstack.core.location")
local fs = require("peekstack.util.fs")

local M = {}

---@param text? string
---@return string
local function normalize_label_text(text)
  if type(text) ~= "string" then
    return ""
  end
  local normalized = text:gsub("[\r\n\t]+", " "):gsub("%s+", " ")
  return vim.trim(normalized)
end

---@param suffix string
---@return string, integer, integer
local function parse_suffix_location(suffix)
  local path, line, col = suffix:match("^(.*):(%d+):(%d+)$")
  if not path then
    return suffix, 0, 0
  end
  return path, tonumber(line) or 0, tonumber(col) or 0
end

---@param loc PeekstackLocation
---@param preview_lines integer
---@param opts PeekstackDisplayTextOpts
---@return { label: string, symbol: string, path: string, display_lnum: integer, display_col: integer }
local function build_location_label_payload(loc, preview_lines, opts)
  local suffix = location.display_text(loc, 0, opts)
  local path, display_lnum, display_col = parse_suffix_location(suffix)
  local symbol = preview_lines > 0 and normalize_label_text(loc.text) or ""
  if symbol == "" then
    return {
      label = suffix,
      symbol = "",
      path = path,
      display_lnum = display_lnum,
      display_col = display_col,
    }
  end
  return {
    label = string.format("%s - %s", symbol, suffix),
    symbol = symbol,
    path = path,
    display_lnum = display_lnum,
    display_col = display_col,
  }
end

---@return PeekstackDisplayTextOpts
local function display_text_opts()
  local ui_path = config.get().ui.path or {}
  local max_width = ui_path.max_width or 0
  if max_width == 0 then
    max_width = math.floor(vim.o.columns * 0.7)
  end
  return {
    path_base = ui_path.base,
    max_width = max_width,
  }
end

---@param locations PeekstackLocation[]
---@param preview_lines integer
---@return PeekstackPickerItem[]
function M.build_items(locations, preview_lines)
  local opts = display_text_opts()
  local items = {}
  for _, loc in ipairs(locations) do
    local payload = build_location_label_payload(loc, preview_lines, opts)
    table.insert(items, {
      label = payload.label,
      value = loc,
    })
  end
  return items
end

---@param locations PeekstackLocation[]
---@param preview_lines integer
---@return PeekstackPickerExternalItem[]
function M.build_external_items(locations, preview_lines)
  local opts = display_text_opts()
  local items = {}
  for _, loc in ipairs(locations) do
    local start = loc.range and loc.range.start or {}
    local payload = build_location_label_payload(loc, preview_lines, opts)
    table.insert(items, {
      label = payload.label,
      symbol = payload.symbol,
      path = payload.path,
      display_lnum = payload.display_lnum,
      display_col = payload.display_col,
      value = loc,
      file = fs.uri_to_fname(loc.uri),
      lnum = (start.line or 0) + 1,
      col = (start.character or 0) + 1,
    })
  end
  return items
end

return M
