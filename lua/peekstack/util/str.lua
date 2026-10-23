local fs = require("peekstack.util.fs")

local M = {}

---@type string?
local cached_cwd = nil

local function refresh_cwd()
  cached_cwd = vim.fn.getcwd()
end

---@param path? string
local function ensure_cwd_cache(path)
  if not cached_cwd then
    refresh_cwd()
    return
  end
  if path and path:find(cached_cwd, 1, true) == 1 then
    return
  end
  local current = vim.fn.getcwd()
  if current ~= cached_cwd then
    cached_cwd = current
  end
end

vim.api.nvim_create_autocmd("DirChanged", {
  group = vim.api.nvim_create_augroup("PeekstackCwdCache", { clear = true }),
  callback = refresh_cwd,
})

---@class PeekstackRelativePathOpts
---@field repo_root_cache? table<string, string|false>

---@param start string
---@param cache table<string, string|false>
---@return string?
local function repo_root_with_cache(start, cache)
  local cached = cache[start]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end
  local resolved = fs.repo_root(start)
  cache[start] = resolved or false
  return resolved
end

---@param path? string
---@return string
function M.shorten_path(path)
  if not path then
    return ""
  end
  ensure_cwd_cache(path)
  local cwd = cached_cwd or ""
  if path:find(cwd, 1, true) == 1 then
    return path:gsub("^" .. vim.pesc(cwd) .. "/?", "")
  end
  return path
end

---@param path? string
---@param base? "repo"|"cwd"|"absolute"
---@param opts? PeekstackRelativePathOpts
---@return string
function M.relative_path(path, base, opts)
  if not path or path == "" then
    return ""
  end
  if base == "absolute" then
    return path
  end
  if base == "repo" then
    local start = vim.fs.dirname(path)
    local repo = nil
    if opts and opts.repo_root_cache then
      repo = repo_root_with_cache(start, opts.repo_root_cache)
    else
      repo = fs.repo_root(start)
    end
    if repo and path:find(repo, 1, true) == 1 then
      return path:gsub("^" .. vim.pesc(repo) .. "/?", "")
    end
  end
  if base == "repo" or base == "cwd" then
    ensure_cwd_cache(path)
    local cwd = cached_cwd or ""
    if path:find(cwd, 1, true) == 1 then
      return path:gsub("^" .. vim.pesc(cwd) .. "/?", "")
    end
  end
  return path
end

---Return the longest prefix of text that fits in width display cells.
---Composing characters stay with their base character.
---@param text string
---@param width integer
---@return string prefix
---@return integer prefix_width
function M.take_width(text, width)
  local used = 0
  local count = vim.fn.strchars(text, true)
  local taken = 0
  while taken < count do
    -- Measured at its column so a tab takes the cells it really spans.
    local char_width = vim.fn.strdisplaywidth(vim.fn.strcharpart(text, taken, 1, true), used)
    if used + char_width > width then
      break
    end
    used = used + char_width
    taken = taken + 1
  end
  return vim.fn.strcharpart(text, 0, taken, true), used
end

---Return the longest suffix of text that fits in width display cells.
---Composing characters stay with their base character.
---@param text string
---@param width integer
---@param col? integer screen column the suffix will start at (default 0)
---@return string suffix
---@return integer suffix_width
function M.take_width_right(text, width, col)
  local used = 0
  local count = vim.fn.strchars(text, true)
  local start = count
  while start > 0 do
    -- A tab's width depends on what precedes it, so the whole suffix is
    -- measured again at the column it will start at.
    local suffix = vim.fn.strcharpart(text, start - 1, count - start + 1, true)
    local suffix_width = vim.fn.strdisplaywidth(suffix, col or 0)
    if suffix_width > width then
      break
    end
    used = suffix_width
    start = start - 1
  end
  return vim.fn.strcharpart(text, start, count - start, true), used
end

---@param text? string
---@param max_width integer
---@return string
function M.truncate_middle(text, max_width)
  if not text then
    return ""
  end
  if max_width <= 0 then
    return ""
  end
  if vim.fn.strdisplaywidth(text) <= max_width then
    return text
  end
  local ellipsis = "..."
  local ellipsis_width = vim.fn.strdisplaywidth(ellipsis)
  if max_width <= ellipsis_width then
    return ellipsis:sub(1, max_width)
  end
  local remaining = max_width - ellipsis_width
  -- A wide character that does not fit on the left hands its cell to the right.
  local left_text, left_width = M.take_width(text, math.ceil(remaining / 2))
  local right_text = M.take_width_right(text, remaining - left_width, left_width + ellipsis_width)
  return left_text .. ellipsis .. right_text
end

return M
