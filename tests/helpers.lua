local M = {}

---@param opts? table
---@return PeekstackLocation
function M.make_location(opts)
  return vim.tbl_extend("force", {
    uri = vim.uri_from_bufnr(0),
    range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
    provider = "test",
  }, opts or {})
end

return M
