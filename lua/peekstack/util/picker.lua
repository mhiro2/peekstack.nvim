local config = require("peekstack.config")
local location = require("peekstack.core.location")

local M = {}

---@param locations PeekstackLocation[]
---@param preview_lines integer
---@return table[]
function M.build_items(locations, preview_lines)
  local ui_path = config.get().ui.path or {}
  local max_width = ui_path.max_width or 0
  if max_width == 0 then
    max_width = math.floor(vim.o.columns * 0.7)
  end
  local opts = {
    path_base = ui_path.base,
    max_width = max_width,
  }
  local items = {}
  for _, loc in ipairs(locations) do
    table.insert(items, {
      label = location.display_text(loc, preview_lines, opts),
      value = loc,
    })
  end
  return items
end

return M
