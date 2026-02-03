local location = require("peekstack.core.location")

local M = {}

---Get diagnostics under cursor
---@param ctx PeekstackProviderContext
---@param cb fun(locations: PeekstackLocation[])
function M.under_cursor(ctx, cb)
  local line = ctx.position and ctx.position.line or 0
  local diags = vim.diagnostic.get(ctx.bufnr, { lnum = line })
  cb(location.from_diagnostics(diags, "diagnostics.under_cursor"))
end

---Get all diagnostics in the current buffer
---@param ctx PeekstackProviderContext
---@param cb fun(locations: PeekstackLocation[])
function M.in_buffer(ctx, cb)
  local diags = vim.diagnostic.get(ctx.bufnr)
  cb(location.from_diagnostics(diags, "diagnostics.in_buffer"))
end

return M
