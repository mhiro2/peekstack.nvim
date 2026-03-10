local dispatch = require("peekstack.dispatch")
local registry = require("peekstack.registry")
local setup = require("peekstack.setup")

local M = {}

M.register_provider = registry.register_provider
M.list_providers = registry.list_providers
M.register_picker = registry.register_picker
M.peek_location = dispatch.peek_location
M.peek_locations = dispatch.peek_locations
M.peek = dispatch.peek

---@param opts? table
function M.setup(opts)
  setup.run(opts)
end

---Proxy table for `peekstack.core.stack`.
---@type table
M.stack = setmetatable({}, {
  __index = function(_, k)
    return require("peekstack.core.stack")[k]
  end,
})

---Proxy table for `peekstack.persist`.
---@type table
M.persist = setmetatable({}, {
  __index = function(_, k)
    return require("peekstack.persist")[k]
  end,
})

---Proxy table for `peekstack.extensions`.
---@type table
M.extensions = setmetatable({}, {
  __index = function(_, k)
    return require("peekstack.extensions")[k]
  end,
})

return M
