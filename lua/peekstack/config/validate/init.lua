local ui = require("peekstack.config.validate.rules.ui")
local picker = require("peekstack.config.validate.rules.picker")
local providers = require("peekstack.config.validate.rules.providers")
local persist = require("peekstack.config.validate.rules.persist")
local unknown = require("peekstack.config.validate.unknown")

local M = {}

---@param cfg table
---@param defaults PeekstackConfig
function M.run(cfg, defaults)
  -- Detect unknown keys first, before field validators can replace invalid
  -- subtrees with defaults (which would hide sibling typos).
  unknown.detect(cfg, defaults)
  ui.validate(cfg, defaults)
  picker.validate(cfg, defaults)
  providers.validate(cfg, defaults)
  persist.validate(cfg, defaults)
end

return M
