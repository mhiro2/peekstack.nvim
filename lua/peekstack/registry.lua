local M = {}

---Providers and pickers registered by `setup()`. Cleared on every `setup()`
---so a re-run reflects the current config (e.g. a provider group disabled).
---@type table<string, fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))>
local builtin_providers = {}
---@type table<string, PeekstackPicker>
local builtin_pickers = {}

---Providers and pickers registered through the public API. These survive
---`setup()` re-runs and take precedence over builtin entries with the same name.
---@type table<string, fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))>
local user_providers = {}
---@type table<string, PeekstackPicker>
local user_pickers = {}

---Clear builtin registrations. User registrations are kept.
function M.reset()
  builtin_providers = {}
  builtin_pickers = {}
end

---@param name string
---@param fn fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))
function M.register_provider(name, fn)
  user_providers[name] = fn
end

---@param name string
---@param fn fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))
function M.register_builtin_provider(name, fn)
  builtin_providers[name] = fn
end

---@return string[]
function M.list_providers()
  local seen = {}
  for name in pairs(builtin_providers) do
    seen[name] = true
  end
  for name in pairs(user_providers) do
    seen[name] = true
  end
  local names = vim.tbl_keys(seen)
  table.sort(names)
  return names
end

---@param name string
---@return fun(ctx: PeekstackProviderContext, cb: fun(locations: PeekstackLocation[]))?
function M.get_provider(name)
  return user_providers[name] or builtin_providers[name]
end

---@param name string
---@param fn PeekstackPicker
function M.register_picker(name, fn)
  user_pickers[name] = fn
end

---@param name string
---@param fn PeekstackPicker
function M.register_builtin_picker(name, fn)
  builtin_pickers[name] = fn
end

---@param name string
---@return boolean
function M.has_user_picker(name)
  return user_pickers[name] ~= nil
end

---@param name string
---@return PeekstackPicker?
function M.get_picker(name)
  return user_pickers[name] or builtin_pickers[name]
end

---@param prefix string
---@param provider_mod table
---@param names string[]
function M.register_provider_group(prefix, provider_mod, names)
  for _, name in ipairs(names) do
    local fn = provider_mod[name]
    if fn then
      M.register_builtin_provider(prefix .. name, fn)
    end
  end
end

return M
