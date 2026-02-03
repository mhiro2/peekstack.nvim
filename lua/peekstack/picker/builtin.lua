local config = require("peekstack.config")
local picker_util = require("peekstack.util.picker")

local M = {}

---Pick a location using vim.ui.select
---@param locations PeekstackLocation[]
---@param opts? table
---@param cb fun(location: PeekstackLocation)
function M.pick(locations, opts, cb)
  local items = picker_util.build_items(locations, config.get().picker.builtin.preview_lines)

  vim.ui.select(items, {
    prompt = opts and opts.prompt or "Select location",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      cb(choice.value)
    end
  end)
end

return M
