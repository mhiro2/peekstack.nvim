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

---@return string
local function cursor_target()
  local target = vim.fn.expand("<cfile>")
  local wide_target = vim.fn.expand("<cWORD>")
  if wide_target ~= "" and wide_target:find(":%d+") and not target:find(":%d+") then
    return wide_target
  end
  return target
end

---Get file path under cursor
---@param ctx PeekstackProviderContext
---@param cb fun(locations: PeekstackLocation[])
function M.under_cursor(ctx, cb)
  local target = cursor_target()
  if not target or target == "" then
    cb({})
    return
  end
  if not target:match("^%a+://") then
    local source_name = vim.api.nvim_buf_get_name(ctx.bufnr)
    local resolved, lnum, col = resolve_target(target, source_name)
    if not resolved then
      cb({})
      return
    end
    target = resolved
    lnum = lnum or 1
    col = col or 1

    local uri = fs.fname_to_uri(target)
    local loc = location.normalize({
      uri = uri,
      range = {
        start = { line = lnum - 1, character = col - 1 },
        ["end"] = { line = lnum - 1, character = col - 1 },
      },
    }, "file.under_cursor")
    cb(loc and { loc } or {})
    return
  end
  local uri = fs.fname_to_uri(target)
  local loc = location.normalize(
    { uri = uri, range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } } },
    "file.under_cursor"
  )
  cb(loc and { loc } or {})
end

return M
