local marks_util = require("peekstack.util.marks")

local M = {}

---@return { include: string, include_special: boolean }
local function get_opts()
  local cfg = require("peekstack.config").get()
  local marks_cfg = cfg.providers.marks
  return {
    include = marks_cfg.include,
    include_special = marks_cfg.include_special,
  }
end

---Get marks in the current buffer
---@param ctx PeekstackProviderContext
---@param cb fun(locations: PeekstackLocation[])
function M.buffer(ctx, cb)
  cb(marks_util.collect("buffer", ctx.bufnr, get_opts()))
end

---Get global marks
---@param ctx PeekstackProviderContext
---@param cb fun(locations: PeekstackLocation[])
function M.global(ctx, cb)
  cb(marks_util.collect("global", ctx.bufnr, get_opts()))
end

---Get all marks (buffer + global)
---@param ctx PeekstackProviderContext
---@param cb fun(locations: PeekstackLocation[])
function M.all(ctx, cb)
  cb(marks_util.collect("all", ctx.bufnr, get_opts()))
end

return M
