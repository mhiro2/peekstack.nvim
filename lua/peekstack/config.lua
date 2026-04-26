local defaults = require("peekstack.config.defaults")
local notify = require("peekstack.util.notify")
local validate = require("peekstack.config.validate")

local M = {}

M.defaults = defaults

---@type PeekstackConfig
local config = vim.deepcopy(M.defaults)

---@param opts? PeekstackConfig
---@return PeekstackConfig
function M.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then
    notify.warn("setup(opts) expects a table; got " .. type(opts) .. ". Falling back to defaults.")
    opts = nil
  end
  config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  validate.run(config, M.defaults)
  return config
end

---@return PeekstackConfig
function M.get()
  return config
end

return M
