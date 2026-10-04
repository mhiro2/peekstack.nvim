local fs = require("peekstack.util.fs")
local location = require("peekstack.core.location")
local notify = require("peekstack.util.notify")

local M = {}

---@param text string?
---@return string
local function compact_message(text)
  local message = (text or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if message == "" then
    return "unknown error"
  end
  return message
end

---@param stderr string?
---@return boolean
local function is_ignore_file_error(stderr)
  local message = compact_message(stderr):lower()
  return message:find(".gitignore", 1, true) ~= nil
    or message:find(".ignore", 1, true) ~= nil
    or message:find(".rgignore", 1, true) ~= nil
    or (message:find("ignore", 1, true) ~= nil and message:find("glob", 1, true) ~= nil)
end

---@param stderr string?
---@return string
local function format_failure_message(stderr)
  local message = compact_message(stderr)
  if is_ignore_file_error(stderr) then
    return "rg failed; check .gitignore/.ignore patterns or encoding: " .. message
  end
  return "rg failed: " .. message
end

---@param path string
---@param cwd string
---@return string
local function resolve_path(path, cwd)
  if vim.fn.isabsolutepath(path) ~= 1 then
    path = vim.fs.joinpath(cwd, path)
  end
  return vim.fs.normalize(path, { expand_env = false })
end

---@param line string
---@param cwd string
---@return string?, integer?, integer?, string?
local function parse_rg_line(line, cwd)
  local candidates = {}
  local search_from = 1

  while true do
    local start_idx, end_idx, lnum, col = line:find(":(%d+):(%d+):", search_from)
    if not start_idx then
      break
    end
    table.insert(candidates, {
      path = line:sub(1, start_idx - 1),
      lnum = tonumber(lnum),
      col = tonumber(col),
      text = line:sub(end_idx + 1),
    })
    search_from = end_idx + 1
  end

  if #candidates == 0 then
    return nil, nil, nil, nil
  end

  for i = #candidates, 1, -1 do
    local candidate = candidates[i]
    local resolved = resolve_path(candidate.path, cwd)
    local stat = vim.uv.fs_stat(resolved)
    if stat and stat.type == "file" then
      return resolved, candidate.lnum, candidate.col, candidate.text
    end
  end

  local candidate = candidates[1]
  return resolve_path(candidate.path, cwd), candidate.lnum, candidate.col, candidate.text
end

---Parse `rg --vimgrep` output, resolving relative paths against the directory rg ran in.
---@param output string
---@param cwd string
---@return PeekstackLocation[]
local function parse_rg_output(output, cwd)
  local items = {}
  for _, line in ipairs(vim.split(output, "\n", { trimempty = true })) do
    local path, lnum, col, text = parse_rg_line(line, cwd)
    if path and lnum and col then
      local uri = fs.fname_to_uri(path)
      local loc = location.normalize({
        uri = uri,
        range = {
          start = { line = lnum - 1, character = col - 1 },
          ["end"] = { line = lnum - 1, character = col - 1 },
        },
        text = text,
      }, "grep.search")
      if loc then
        table.insert(items, loc)
      end
    end
  end
  return items
end

---@param _ PeekstackProviderContext
---@param cb fun(locations: PeekstackLocation[])
function M.search(_, cb)
  if vim.fn.executable("rg") ~= 1 then
    notify.warn("rg not found in PATH")
    cb({})
    return
  end

  -- Pin the directory before prompting so a later :cd cannot split the search
  -- and the path resolution between two directories.
  local cwd = vim.fn.getcwd()

  vim.ui.input({ prompt = "rg > " }, function(query)
    if not query or query == "" then
      cb({})
      return
    end

    vim.system({ "rg", "--vimgrep", "--max-count=1000", "--", query }, { cwd = cwd, text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 and result.code ~= 1 then
          notify.warn(format_failure_message(result.stderr))
          cb({})
          return
        end
        cb(parse_rg_output(result.stdout or "", cwd))
      end)
    end)
  end)
end

---Expose parser for tests.
M._parse_output = parse_rg_output
M._format_failure_message = format_failure_message

return M
