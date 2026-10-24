local fs = require("peekstack.util.fs")
local location = require("peekstack.core.location")

local M = {}

---@param path string
---@return boolean
local function is_absolute(path)
  return path:sub(1, 1) == "/" or path:sub(1, 1) == "~" or path:match("^%a:[/\\]") ~= nil or path:sub(1, 2) == "\\\\"
end

---@param target string
---@return string, integer?, integer?
local function parse_target_spec(target)
  local path, lnum, col = target:match("^(.*):(%d+):(%d+)$")
  if path then
    -- Avoid treating Windows drive letter colon as line separator
    if not path:match("^%a:$") then
      return path, tonumber(lnum), tonumber(col)
    end
  end

  path, lnum = target:match("^(.*):(%d+)$")
  if path then
    if not path:match("^%a:$") then
      return path, tonumber(lnum), nil
    end
  end

  return target, nil, nil
end

---@param path string
---@param source_name string
---@return string
local function resolve_path(path, source_name)
  if is_absolute(path) then
    return vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  end

  local base = vim.fn.fnamemodify(source_name, ":p:h")
  if base == "" then
    return vim.fn.fnamemodify(path, ":p")
  end

  return vim.fn.fnamemodify(base .. "/" .. path, ":p")
end

---@param target string
---@param source_name string
---@return string?, integer?, integer?
local function resolve_target(target, source_name)
  -- 1) Try the target string as-is (handles absolute paths and env-var expansions)
  local exact = vim.fn.expand(target)
  local stat = vim.uv.fs_stat(exact)
  if stat then
    if stat.type ~= "file" then
      return nil, nil, nil
    end
    return vim.fn.fnamemodify(exact, ":p"), nil, nil
  end

  -- 2) Resolve relative to the source buffer's directory (the target may be a
  --    relative path that doesn't exist from cwd but does from the source file)
  local raw_resolved = resolve_path(target, source_name)
  local raw_stat = vim.uv.fs_stat(raw_resolved)
  if raw_stat then
    if raw_stat.type ~= "file" then
      return nil, nil, nil
    end
    return raw_resolved, nil, nil
  end

  -- 3) Strip :line[:col] suffix and retry – the suffix prevented fs_stat above
  local path, lnum, col = parse_target_spec(target)
  local resolved = resolve_path(path, source_name)
  local resolved_stat = vim.uv.fs_stat(resolved)
  if not resolved_stat or resolved_stat.type ~= "file" then
    return nil, nil, nil
  end

  return resolved, lnum, col
end

-- A path with a :line[:col] suffix inside a WORD, without the quotes,
-- brackets and separators that wrap a reference in prose or markup.
local SPEC_PATTERN = "[^%s\"'`%(%)%[%]<>{},;]+:%d+[:%d]*"

---Byte offset of the cursor inside the WORD under it, if it is on one.
---@param word string
---@return integer?
local function cursor_offset_in(word)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  if line:sub(col, col):match("^%s?$") then
    return nil
  end
  local start = col
  while start > 1 and not line:sub(start - 1, start - 1):match("%s") do
    start = start - 1
  end
  if line:sub(start, start + #word - 1) ~= word then
    return nil
  end
  return col - start + 1
end

---Candidate references under the cursor, most likely first.
---@return string[]
local function cursor_targets()
  local target = vim.fn.expand("<cfile>")
  if target:match("^%a+://") or target:find(":%d+") then
    return { target }
  end

  local word = vim.fn.expand("<cWORD>")
  if not word:find(":%d+") then
    return target ~= "" and { target } or {}
  end

  -- <cfile> drops the :line[:col] suffix. The whole WORD comes first since
  -- file names may contain punctuation, then the WORD without the quotes or
  -- brackets around it, then the spec cut out of it under the cursor, then
  -- <cfile> itself, and only then specs elsewhere in the WORD.
  local candidates = { word }
  local unwrapped = word:gsub("^[\"'`%(%[<{]+", ""):gsub("[\"'`%)%]>},;.]+$", "")
  if unwrapped ~= word and unwrapped ~= "" then
    table.insert(candidates, unwrapped)
  end
  local offset = cursor_offset_in(word)
  local elsewhere = {}
  local init = 1
  while true do
    local spec_start, spec_end = word:find(SPEC_PATTERN, init)
    if not spec_start then
      break
    end
    local spec = word:sub(spec_start, spec_end):gsub(":+$", "")
    if offset and offset >= spec_start and offset <= spec_end then
      table.insert(candidates, spec)
    else
      table.insert(elsewhere, spec)
    end
    init = spec_end + 1
  end
  if target ~= "" then
    table.insert(candidates, target)
  end
  return vim.list_extend(candidates, elsewhere)
end

---@param uri string
---@param lnum integer
---@param col integer
---@return PeekstackLocation[]
local function locations_at(uri, lnum, col)
  local loc = location.normalize({
    uri = uri,
    range = {
      start = { line = lnum - 1, character = col - 1 },
      ["end"] = { line = lnum - 1, character = col - 1 },
    },
  }, "file.under_cursor")
  return loc and { loc } or {}
end

---Get file path under cursor
---@param ctx PeekstackProviderContext
---@param cb fun(locations: PeekstackLocation[])
function M.under_cursor(ctx, cb)
  local targets = cursor_targets()
  if #targets == 1 and targets[1]:match("^%a+://") then
    cb(locations_at(fs.fname_to_uri(targets[1]), 1, 1))
    return
  end
  local source_name = vim.api.nvim_buf_get_name(ctx.bufnr)
  for _, target in ipairs(targets) do
    local resolved, lnum, col = resolve_target(target, source_name)
    if resolved then
      cb(locations_at(fs.fname_to_uri(resolved), lnum or 1, col or 1))
      return
    end
  end
  cb({})
end

return M
