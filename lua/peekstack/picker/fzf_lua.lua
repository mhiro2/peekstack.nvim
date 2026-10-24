local picker_util = require("peekstack.util.picker")
local notify = require("peekstack.util.notify")

local M = {}

---Pick a location using fzf-lua
---@param locations PeekstackLocation[]
---@param opts? table
---@param cb fun(location: PeekstackLocation)
function M.pick(locations, opts, cb)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    notify.warn("fzf-lua not available")
    return
  end

  local items = picker_util.build_external_items(locations, 1)
  for idx, item in ipairs(items) do
    item.index = idx
  end

  local user_opts = opts or {}
  local fzf_opts = vim.tbl_extend("force", user_opts.fzf_opts or {}, {
    ["--delimiter"] = "\t",
    ["--with-nth"] = "2",
    ["--nth"] = "2",
  })

  ---@type table
  local exec_opts = vim.tbl_deep_extend("force", user_opts, {
    prompt = "Peekstack> ",
    previewer = "builtin",
    fzf_opts = fzf_opts,
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

  -- Control characters would split an entry into several fzf lines or shift
  -- the tab-delimited fields, so both visible fields are sanitized.
  local lines = {}
  for _, item in ipairs(items) do
    local file = (item.file or ""):gsub("[\r\n\t]", " ")
    local label = item.label:gsub("[\r\n\t]", " ")
    local loc = string.format("%s:%d:%d", file, item.lnum, item.col)
    table.insert(lines, string.format("%s\t%s\t%d", loc, label, item.index))
  end

  -- fzf-lua streams a table of strings line by line. A function source would
  -- have to push each line through its write callback instead of returning
  -- them, so the prepared table is passed directly.
  fzf.fzf_exec(lines, exec_opts)
end

return M
