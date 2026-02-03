local fs = require("peekstack.util.fs")

local M = {}

local SPECIAL_MARKS = "'`^.<>[]\""

---@param mark_char string
---@param include string
---@param include_special boolean
---@return boolean
local function is_included(mark_char, include, include_special)
  if not include_special and SPECIAL_MARKS:find(mark_char, 1, true) then
    return false
  end
  if include:find(mark_char, 1, true) then
    return true
  end
  return false
end

---@param entry table
---@param bufnr integer
---@param provider string
---@return PeekstackLocation?
local function entry_to_location(entry, bufnr, provider)
  local mark_char = entry.mark:sub(2) -- strip leading '
  local pos = entry.pos
  if not pos then
    return nil
  end

  local lnum = pos[2]
  local col = math.max((pos[3] or 1) - 1, 0)

  -- skip marks with line number 0
  if lnum == 0 then
    return nil
  end

  local uri
  if entry.file then
    local fname = vim.fn.fnamemodify(entry.file, ":p")
    uri = fs.fname_to_uri(fname)
  else
    uri = vim.uri_from_bufnr(bufnr)
  end

  if not uri or uri == "" then
    return nil
  end

  -- get line text from loaded buffer only
  local text = ""
  local target_bufnr = entry.file and vim.fn.bufnr(entry.file) or bufnr
  if target_bufnr >= 0 and vim.api.nvim_buf_is_loaded(target_bufnr) then
    local lines = vim.api.nvim_buf_get_lines(target_bufnr, lnum - 1, lnum, false)
    if lines and lines[1] then
      text = lines[1]
    end
  end

  local display = "[" .. mark_char .. "] " .. text

  return {
    uri = uri,
    range = {
      start = { line = lnum - 1, character = col },
      ["end"] = { line = lnum - 1, character = col },
    },
    text = display,
    provider = provider,
  }
end

---Collect marks and return as PeekstackLocation[]
---@param scope "buffer"|"global"|"all"
---@param bufnr integer
---@param opts { include: string, include_special: boolean }
---@return PeekstackLocation[]
function M.collect(scope, bufnr, opts)
  local include = opts.include or "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local include_special = opts.include_special or false

  local raw_marks = {}

  if scope == "buffer" or scope == "all" then
    local local_marks = vim.fn.getmarklist(bufnr)
    for _, entry in ipairs(local_marks) do
      local mark_char = entry.mark:sub(2)
      if is_included(mark_char, include, include_special) then
        table.insert(raw_marks, { entry = entry, bufnr = bufnr, provider = "marks.buffer" })
      end
    end
  end

  if scope == "global" or scope == "all" then
    local global_marks = vim.fn.getmarklist()
    for _, entry in ipairs(global_marks) do
      local mark_char = entry.mark:sub(2)
      if is_included(mark_char, include, include_special) then
        table.insert(raw_marks, { entry = entry, bufnr = bufnr, provider = "marks.global" })
      end
    end
  end

  -- sort by mark character
  table.sort(raw_marks, function(a, b)
    return a.entry.mark < b.entry.mark
  end)

  local locations = {}
  for _, item in ipairs(raw_marks) do
    local loc = entry_to_location(item.entry, item.bufnr, item.provider)
    if loc then
      table.insert(locations, loc)
    end
  end

  return locations
end

return M
