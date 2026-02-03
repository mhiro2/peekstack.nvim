local fs = require("peekstack.util.fs")
local location = require("peekstack.core.location")

local M = {}

---Get file path under cursor
---@param ctx PeekstackProviderContext
---@param cb fun(locations: PeekstackLocation[])
function M.under_cursor(ctx, cb)
  local target = vim.fn.expand("<cfile>")
  if not target or target == "" then
    cb({})
    return
  end
  if not target:match("^%a+://") then
    local source_name = vim.api.nvim_buf_get_name(ctx.bufnr)
    local base = vim.fn.fnamemodify(source_name, ":p:h")
    target = vim.fn.fnamemodify(base .. "/" .. target, ":p")
  end
  local uri = fs.fname_to_uri(target)
  local loc = location.normalize(
    { uri = uri, range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } } },
    "file.under_cursor"
  )
  cb(loc and { loc } or {})
end

return M
