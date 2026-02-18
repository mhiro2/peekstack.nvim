local M = {}

--- Convert picker entry to PeekstackLocation and push it.
---@param entry { filename: string, lnum?: integer, col?: integer }
---@param opts? { provider?: string, mode?: string }
function M.push_entry(entry, opts)
  if not entry or not entry.filename then
    return
  end
  local location = require("peekstack.core.location")
  local peekstack = require("peekstack")
  local loc = location.normalize({
    filename = entry.filename,
    lnum = entry.lnum or 1,
    col = entry.col or 1,
  }, opts and opts.provider or "extension")
  if loc then
    peekstack.peek_location(loc, opts)
  end
end

return M
