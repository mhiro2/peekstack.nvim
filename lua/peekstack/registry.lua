local M = {}

---@type table<string, fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))>
local providers = {}

---@type table<string, PeekstackPicker>
local pickers = {}

function M.reset()
  providers = {}
  pickers = {}
end

---@param name string
---@param fn fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))
function M.register_provider(name, fn)
  providers[name] = fn
end

---@return string[]
function M.list_providers()
  local names = vim.tbl_keys(providers)
  table.sort(names)
  return names
end

---@param name string
---@return fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))?
function M.get_provider(name)
  return providers[name]
end

---@param name string
---@param fn PeekstackPicker
function M.register_picker(name, fn)
  pickers[name] = fn
end

---@param name string
---@return PeekstackPicker?
function M.get_picker(name)
  return pickers[name]
end

---@param prefix string
---@param provider_mod table
---@param names string[]
function M.register_provider_group(prefix, provider_mod, names)
  for _, name in ipairs(names) do
    local fn = provider_mod[name]
    if fn then
      M.register_provider(prefix .. name, fn)
    end
  end
end

return M
