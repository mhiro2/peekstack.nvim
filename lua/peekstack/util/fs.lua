local M = {}

---@type string?
local cached_repo_root = nil
---@type string?
local cached_repo_cwd = nil
---@type string?
local cached_scope_base = nil
local scope_base_ready = false

local function reset_repo_root_cache()
  cached_repo_root = nil
  cached_repo_cwd = nil
end

local function reset_scope_base_cache()
  cached_scope_base = nil
  scope_base_ready = false
end

---@return string
local function scope_base_dir()
  local base = vim.fn.stdpath("state") .. "/peekstack"
  if cached_scope_base ~= base then
    cached_scope_base = base
    scope_base_ready = false
  end
  if not scope_base_ready then
    M.ensure_dir(base)
    scope_base_ready = true
  end
  return base
end

vim.api.nvim_create_autocmd("DirChanged", {
  group = vim.api.nvim_create_augroup("PeekstackRepoRootCache", { clear = true }),
  callback = reset_repo_root_cache,
})

---@param uri? string
---@return string?
function M.uri_to_fname(uri)
  if not uri then
    return nil
  end
  return vim.uri_to_fname(uri)
end

---@param fname? string
---@return string?
function M.fname_to_uri(fname)
  if not fname then
    return nil
  end
  return vim.uri_from_fname(fname)
end

---@param start? string
---@return string?
function M.repo_root(start)
  local path = start or vim.fn.getcwd()
  if not start and cached_repo_cwd == path then
    return cached_repo_root
  end
  local root = vim.fs.find(".git", { upward = true, path = path })[1]
  local repo_root = root and vim.fs.dirname(root) or nil
  if not start then
    cached_repo_cwd = path
    cached_repo_root = repo_root
  end
  return repo_root
end

---Reset internal cache (for testing).
function M._reset_repo_root_cache()
  reset_repo_root_cache()
end

---Reset scope-path cache (for testing).
function M._reset_scope_path_cache()
  reset_scope_base_cache()
end

---@param path string
---@return string
function M.ensure_dir(path)
  if vim.fn.isdirectory(path) == 1 then
    return path
  end
  vim.fn.mkdir(path, "p")
  return path
end

---@param input? string
---@return string
function M.slug(input)
  if not input or input == "" then
    return "default"
  end
  local ok, sha = pcall(vim.fn.sha256, input)
  if ok and type(sha) == "string" and #sha > 0 then
    return sha
  end
  return (input:gsub("[^%w%-_.]", "_"))
end

---@param scope string
---@return string
function M.scope_path(scope)
  local base = scope_base_dir()
  if scope == "global" then
    return base .. "/global.json"
  end
  if scope == "cwd" then
    return base .. "/cwd_" .. M.slug(vim.fn.getcwd()) .. ".json"
  end
  local repo = M.repo_root()
  if repo then
    return base .. "/repo_" .. M.slug(repo) .. ".json"
  end
  return base .. "/cwd_" .. M.slug(vim.fn.getcwd()) .. ".json"
end

---@param bufnr integer
---@param buftype string?
---@param bufhidden string?
function M.configure_buffer(bufnr, buftype, bufhidden)
  buftype = buftype or "nofile"
  bufhidden = bufhidden or "wipe"
  vim.bo[bufnr].buftype = buftype
  vim.bo[bufnr].bufhidden = bufhidden
  vim.bo[bufnr].swapfile = false
end

return M
