local picker_util = require("peekstack.util.picker")

local M = {}

---Pick a location using fzf-lua
---@param locations PeekstackLocation[]
---@param opts? table
---@param cb fun(location: PeekstackLocation)
function M.pick(locations, opts, cb)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua not available", vim.log.levels.WARN)
    return
  end

  local items = picker_util.build_external_items(locations, 1)
  for idx, item in ipairs(items) do
    item.index = idx
  end

  ---@type table
  local exec_opts = vim.tbl_extend("force", opts or {}, {
    prompt = "Peekstack> ",
    previewer = "builtin",
    actions = {
      ["default"] = function(selected)
        if not selected or not selected[1] then
          return
        end
        local idx = tonumber(selected[1]:match("\t(%d+)$"))
        local item = idx and items[idx]
        if item then
          cb(item.value)
        end
      end,
    },
  })

  fzf.fzf_exec(function()
    local lines = {}
    for _, item in ipairs(items) do
      local file = item.file or ""
      local label = item.label:gsub("[%r\n\t]", " ")
      table.insert(lines, string.format("%s:%d:%d:%s\t%d", file, item.lnum, item.col, label, item.index))
    end
    return lines
  end, exec_opts)
end

return M
