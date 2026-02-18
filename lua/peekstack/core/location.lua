local fs = require("peekstack.util.fs")
local str = require("peekstack.util.str")

local M = {}

local REALPATH_CACHE_MAX = 512

---@type table<string, string>
local realpath_cache = {}
---@type table<string, { prev: string?, next: string? }>
local realpath_cache_nodes = {}
---@type string?
local realpath_cache_head = nil
---@type string?
local realpath_cache_tail = nil
local realpath_cache_size = 0

---@param key string
local function cache_detach(key)
  local node = realpath_cache_nodes[key]
  if not node then
    return
  end

  local prev = node.prev
  local next = node.next

  if prev then
    realpath_cache_nodes[prev].next = next
  else
    realpath_cache_head = next
  end

  if next then
    realpath_cache_nodes[next].prev = prev
  else
    realpath_cache_tail = prev
  end

  node.prev = nil
  node.next = nil
end

---@param key string
local function cache_append_tail(key)
  if not realpath_cache_nodes[key] then
    realpath_cache_nodes[key] = {}
  end

  local node = realpath_cache_nodes[key]
  node.prev = realpath_cache_tail
  node.next = nil

  if realpath_cache_tail then
    realpath_cache_nodes[realpath_cache_tail].next = key
  else
    realpath_cache_head = key
  end
  realpath_cache_tail = key
end

---@param key string
---@param is_new boolean
local function cache_touch(key, is_new)
  if not is_new and realpath_cache_tail == key then
    return
  end

  if not is_new then
    cache_detach(key)
  else
    realpath_cache_size = realpath_cache_size + 1
  end
  cache_append_tail(key)
end

local function cache_evict_if_needed()
  while realpath_cache_size > REALPATH_CACHE_MAX do
    local evict_key = realpath_cache_head
    if not evict_key then
      break
    end
    cache_detach(evict_key)
    realpath_cache_nodes[evict_key] = nil
    realpath_cache[evict_key] = nil
    realpath_cache_size = realpath_cache_size - 1
  end
end

local function cache_clear()
  realpath_cache = {}
  realpath_cache_nodes = {}
  realpath_cache_head = nil
  realpath_cache_tail = nil
  realpath_cache_size = 0
end

---@param fname string
---@param cache? table<string, string>
---@return string
local function resolve_realpath(fname, cache)
  if cache then
    if cache[fname] then
      return cache[fname]
    end
    local resolved = vim.uv.fs_realpath(fname) or fname
    cache[fname] = resolved
    return resolved
  end

  if realpath_cache[fname] then
    cache_touch(fname, false)
    return realpath_cache[fname]
  end

  local resolved = vim.uv.fs_realpath(fname) or fname
  realpath_cache[fname] = resolved
  cache_touch(fname, true)
  cache_evict_if_needed()
  return resolved
end

---@param range? PeekstackRange
---@return PeekstackRange
local function normalize_range(range)
  if not range then
    return { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } }
  end
  return range
end

---@param loc table
---@param provider? string
---@return PeekstackLocation?
local function from_lsp_location(loc, provider)
  if not loc then
    return nil
  end
  local uri = loc.uri or loc.targetUri
  local range = loc.range or loc.targetRange
  if not uri or not range then
    return nil
  end
  return {
    uri = uri,
    range = normalize_range(range),
    text = loc.text,
    kind = loc.kind,
    provider = provider,
    origin = loc.originSelectionRange,
  }
end

---@param loc table
---@param provider? string
---@return PeekstackLocation?
function M.normalize(loc, provider)
  if not loc then
    return nil
  end
  if loc.uri or loc.targetUri then
    return from_lsp_location(loc, provider)
  end
  if loc.filename or loc.bufnr then
    local uri = loc.uri or fs.fname_to_uri(loc.filename or vim.api.nvim_buf_get_name(loc.bufnr))
    local line = (loc.lnum or 1) - 1
    local col = (loc.col or 1) - 1
    return {
      uri = uri,
      range = {
        start = { line = line, character = col },
        ["end"] = { line = line, character = col },
      },
      text = loc.text,
      kind = loc.kind,
      provider = provider,
    }
  end
  return nil
end

---@param result table|table[]?
---@param provider? string
---@return PeekstackLocation[]
function M.list_from_lsp(result, provider)
  if not result then
    return {}
  end
  local items = {}
  if vim.islist(result) then
    for _, loc in ipairs(result) do
      local norm = from_lsp_location(loc, provider)
      if norm then
        table.insert(items, norm)
      end
    end
  else
    local norm = from_lsp_location(result, provider)
    if norm then
      table.insert(items, norm)
    end
  end
  return items
end

---@param diags table[]?
---@param provider? string
---@return PeekstackLocation[]
function M.from_diagnostics(diags, provider)
  local items = {}
  for _, diag in ipairs(diags or {}) do
    local uri = fs.fname_to_uri(vim.api.nvim_buf_get_name(diag.bufnr or 0))
    table.insert(items, {
      uri = uri,
      range = {
        start = { line = diag.lnum, character = diag.col or 0 },
        ["end"] = { line = diag.end_lnum or diag.lnum, character = diag.end_col or diag.col or 0 },
      },
      text = diag.message,
      kind = diag.severity,
      provider = provider,
    })
  end
  return items
end

---@param location PeekstackLocation
---@param preview_lines? integer
---@param opts? PeekstackDisplayTextOpts
---@return string
function M.display_text(location, preview_lines, opts)
  opts = opts or {}
  local raw_path = fs.uri_to_fname(location.uri) or ""
  local path = raw_path
  if opts.path_base then
    path = str.relative_path(raw_path, opts.path_base)
  else
    path = str.shorten_path(raw_path)
  end
  local line = (location.range.start.line or 0) + 1
  local col = (location.range.start.character or 0) + 1
  local text = location.text or ""
  if preview_lines and preview_lines > 0 and text ~= "" then
    text = text:gsub("\n", " ")
  else
    text = ""
  end
  local suffix = text ~= "" and (" " .. text) or ""
  local suffix_text = string.format(":%d:%d%s", line, col, suffix)
  if opts.max_width and opts.max_width > 0 then
    local suffix_width = vim.fn.strdisplaywidth(suffix_text)
    local available = math.max(opts.max_width - suffix_width, 0)
    path = str.truncate_middle(path, available)
  end
  local label = path .. suffix_text
  if opts.max_width and opts.max_width > 0 and vim.fn.strdisplaywidth(label) > opts.max_width then
    label = str.truncate_middle(label, opts.max_width)
  end
  return label
end

---@param location PeekstackLocation
---@param uri string
---@param line integer
---@param character integer
---@param opts? { realpath_cache?: table<string, string> }
---@return boolean
function M.is_same_position(location, uri, line, character, opts)
  if not location or not location.uri or not location.range or not location.range.start then
    return false
  end
  opts = opts or {}
  local path_cache = opts.realpath_cache
  local loc_uri = location.uri
  local loc_fname = fs.uri_to_fname(loc_uri)
  local cur_fname = fs.uri_to_fname(uri)
  if loc_fname then
    loc_fname = resolve_realpath(loc_fname, path_cache)
  end
  if cur_fname then
    cur_fname = resolve_realpath(cur_fname, path_cache)
  end
  if loc_fname and cur_fname then
    if loc_fname ~= cur_fname then
      return false
    end
  elseif loc_uri ~= uri then
    return false
  end

  local range = location.range
  local start = range.start or { line = 0, character = 0 }
  local finish = range["end"] or start
  local pos = { line = line or 0, character = character or 0 }

  if pos.line < (start.line or 0) then
    return false
  end
  if pos.line == (start.line or 0) and pos.character < (start.character or 0) then
    return false
  end
  if pos.line > (finish.line or 0) then
    return false
  end
  if pos.line == (finish.line or 0) and pos.character > (finish.character or 0) then
    return false
  end
  return true
end

---Reset internal caches (for testing).
function M._reset()
  cache_clear()
end

---@return integer
function M._realpath_cache_limit()
  return REALPATH_CACHE_MAX
end

return M
