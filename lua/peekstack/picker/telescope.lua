local picker_util = require("peekstack.util.picker")
local notify = require("peekstack.util.notify")

local M = {}

---@param primary string
---@param fallback string
---@return string
local function hl(primary, fallback)
  if vim.fn.hlexists(primary) == 1 then
    return primary
  end
  return fallback
end

---Build the display string and its byte-range highlights in the shape Telescope
---expects from `entry.display`: `{ { { start, finish }, hl_group }, ... }`.
---@param item PeekstackPickerExternalItem
---@return string, table
local function display_entry(item)
  local chunks = {}
  if type(item.symbol) == "string" and item.symbol ~= "" then
    chunks[#chunks + 1] = { item.symbol, hl("TelescopeResultsIdentifier", "Function") }
    chunks[#chunks + 1] = { " - ", hl("TelescopeResultsComment", "Comment") }
  end

  local path = item.path or item.label
  picker_util.append_path_chunks(
    chunks,
    path,
    hl("TelescopeResultsComment", "Comment"),
    hl("TelescopeResultsIdentifier", "Directory")
  )

  if type(item.display_lnum) == "number" and item.display_lnum > 0 then
    chunks[#chunks + 1] = { ":", hl("TelescopeResultsComment", "Comment") }
    chunks[#chunks + 1] = { tostring(item.display_lnum), hl("TelescopeResultsNumber", "Number") }
  end

  if type(item.display_col) == "number" and item.display_col > 0 then
    chunks[#chunks + 1] = { ":", hl("TelescopeResultsComment", "Comment") }
    chunks[#chunks + 1] = { tostring(item.display_col), hl("TelescopeResultsNumber", "Number") }
  end

  local texts = {}
  local highlights = {}
  local offset = 0
  for _, chunk in ipairs(chunks) do
    local text = chunk[1]
    texts[#texts + 1] = text
    highlights[#highlights + 1] = { { offset, offset + #text }, chunk[2] }
    offset = offset + #text
  end
  return table.concat(texts), highlights
end

---Pick a location using Telescope
---@param locations PeekstackLocation[]
---@param opts? table
---@param cb fun(location: PeekstackLocation)
function M.pick(locations, opts, cb)
  local ok, telescope = pcall(require, "telescope.pickers")
  if not ok then
    notify.warn("telescope not available")
    return
  end
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local telescope_opts = opts or {}
  local items = picker_util.build_external_items(locations, 1)
  local entries = {}
  for _, item in ipairs(items) do
    table.insert(entries, {
      value = item.value,
      display = function()
        return display_entry(item)
      end,
      ordinal = string.format("%s %s", item.label, item.file or ""),
      filename = item.file,
      lnum = item.lnum,
      col = item.col,
    })
  end

  telescope
    .new(telescope_opts, {
      prompt_title = "Peekstack",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return entry
        end,
      }),
      sorter = conf.generic_sorter(telescope_opts),
      previewer = conf.grep_previewer(telescope_opts),
      attach_mappings = function(_, map)
        local function on_select(bufnr)
          local selection = require("telescope.actions.state").get_selected_entry()
          require("telescope.actions").close(bufnr)
          if selection and selection.value then
            cb(selection.value)
          end
        end
        map("i", "<CR>", on_select)
        map("n", "<CR>", on_select)
        return true
      end,
    })
    :find()
end

return M
