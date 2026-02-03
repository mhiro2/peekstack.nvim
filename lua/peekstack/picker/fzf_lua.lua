local picker_util = require("peekstack.util.picker")

local M = {}

---Pick a location using fzf-lua
---@param locations PeekstackLocation[]
---@param opts? table
---@param cb fun(location: PeekstackLocation)
function M.pick(locations, _opts, cb)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua not available", vim.log.levels.WARN)
    return
  end

  local items = picker_util.build_items(locations, 1)
  for idx, item in ipairs(items) do
    item.index = idx
  end

  fzf.fzf_exec(function()
    local lines = {}
    for _, item in ipairs(items) do
      table.insert(lines, string.format("%d\t%s", item.index, item.label))
    end
    return lines
  end, {
    prompt = "Peekstack> ",
    actions = {
      ["default"] = function(selected)
        if not selected or not selected[1] then
          return
        end
        local idx = tonumber(selected[1]:match("^(%d+)"))
        local item = idx and items[idx]
        if item then
          cb(item.value)
        end
      end,
    },
  })
end

return M
