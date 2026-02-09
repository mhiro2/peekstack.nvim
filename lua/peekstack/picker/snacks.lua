local picker_util = require("peekstack.util.picker")

local M = {}

---Pick a location using snacks.nvim picker
---@param locations PeekstackLocation[]
---@param opts? table
---@param cb fun(location: PeekstackLocation)
function M.pick(locations, opts, cb)
  local ok, snacks = pcall(require, "snacks.picker")
  if not ok then
    vim.notify("snacks.nvim not available", vim.log.levels.WARN)
    return
  end

  local raw_items = picker_util.build_external_items(locations, 1)
  local items = {}
  for _, item in ipairs(raw_items) do
    local loc = item.value
    local start = loc.range and loc.range.start or {}
    table.insert(items, {
      text = item.label,
      file = item.file or loc.uri,
      pos = { item.lnum, start.character or 0 },
      peekstack_loc = loc,
    })
  end

  local picker_opts = vim.tbl_extend("force", opts or {}, {
    title = "Peekstack",
    items = items,
    format = "file",
    confirm = function(picker, item)
      if item and item.peekstack_loc then
        picker:close()
        cb(item.peekstack_loc)
      end
    end,
  })

  snacks.pick(picker_opts)
end

return M
