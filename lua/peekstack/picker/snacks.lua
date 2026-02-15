local picker_util = require("peekstack.util.picker")

local M = {}

---@param chunks table
---@param path string
local function append_path_chunks(chunks, path)
  local dir, base = path:match("^(.*[/\\])(.+)$")
  if dir and base then
    chunks[#chunks + 1] = { dir, "SnacksPickerDir" }
    chunks[#chunks + 1] = { base, "SnacksPickerFile" }
    return
  end
  chunks[#chunks + 1] = { path, "SnacksPickerFile" }
end

---@param item table
---@return table
local function format_item(item)
  local chunks = {}
  local symbol = item.symbol
  if type(symbol) == "string" and symbol ~= "" then
    chunks[#chunks + 1] = { symbol, "SnacksPickerLabel" }
    chunks[#chunks + 1] = { " - ", "SnacksPickerDelim" }
  end

  local path = item.path
  if type(path) ~= "string" or path == "" then
    path = item.text or ""
  end
  append_path_chunks(chunks, path)

  if type(item.display_lnum) == "number" and item.display_lnum > 0 then
    chunks[#chunks + 1] = { ":", "SnacksPickerDelim" }
    chunks[#chunks + 1] = { tostring(item.display_lnum), "SnacksPickerRow" }
  end

  if type(item.display_col) == "number" and item.display_col > 0 then
    chunks[#chunks + 1] = { ":", "SnacksPickerDelim" }
    chunks[#chunks + 1] = { tostring(item.display_col), "SnacksPickerCol" }
  end

  return chunks
end

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
      symbol = item.symbol,
      path = item.path,
      display_lnum = item.display_lnum,
      display_col = item.display_col,
      file = item.file or loc.uri,
      pos = { item.lnum, start.character or 0 },
      peekstack_loc = loc,
    })
  end

  local picker_opts = vim.tbl_extend("force", opts or {}, {
    title = "Peekstack",
    items = items,
    format = format_item,
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
