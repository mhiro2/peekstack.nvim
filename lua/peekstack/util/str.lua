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
---@return string
function M.breadcrumb_path(path)
  if not path or path == "" then
    return ""
  end
  local normalized = path:gsub("\\", "/")
  local parts = vim.split(normalized, "/", { plain = true, trimempty = true })
  if #parts == 0 then
    return ""
  end
  return table.concat(parts, " > ")
end

---@param path? string
---@param base? "repo"|"cwd"|"absolute"
---@return string
function M.relative_path(path, base)
  if not path or path == "" then
    return ""
  end
  if base == "absolute" then
    return path
  end
  if base == "repo" then
    local repo = fs.repo_root(vim.fs.dirname(path))
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
  local left = math.ceil(remaining / 2)
  local right = remaining - left
  local total_chars = vim.fn.strchars(text)
  local left_text = vim.fn.strcharpart(text, 0, left)
  local right_text = vim.fn.strcharpart(text, math.max(total_chars - right, 0), right)
  return left_text .. ellipsis .. right_text
end

---@param fmt? string
---@param data table<string, any>
---@return string
function M.format_title(fmt, data)
  if not fmt then
    return ""
  end
  return (fmt:gsub("{(.-)}", function(key)
    return tostring(data[key] or "")
  end))
end

return M
