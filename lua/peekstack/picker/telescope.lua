local picker_util = require("peekstack.util.picker")

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

---@param chunks table
---@param path string
local function append_path_chunks(chunks, path)
  local dir, base = path:match("^(.*[/\\])(.+)$")
  if dir and base then
    chunks[#chunks + 1] = { dir, hl("TelescopeResultsComment", "Comment") }
    chunks[#chunks + 1] = { base, hl("TelescopeResultsIdentifier", "Directory") }
    return
  end
  chunks[#chunks + 1] = { path, hl("TelescopeResultsIdentifier", "Directory") }
end

---@param displayer fun(chunks: table): string
---@param item PeekstackPickerExternalItem
---@return string
local function display_entry(displayer, item)
  local chunks = {}
  if type(item.symbol) == "string" and item.symbol ~= "" then
    chunks[#chunks + 1] = { item.symbol, hl("TelescopeResultsIdentifier", "Function") }
    chunks[#chunks + 1] = { " - ", hl("TelescopeResultsComment", "Comment") }
  end

  local path = item.path or item.label
  append_path_chunks(chunks, path)

  if type(item.display_lnum) == "number" and item.display_lnum > 0 then
    chunks[#chunks + 1] = { ":", hl("TelescopeResultsComment", "Comment") }
    chunks[#chunks + 1] = { tostring(item.display_lnum), hl("TelescopeResultsNumber", "Number") }
  end

  if type(item.display_col) == "number" and item.display_col > 0 then
    chunks[#chunks + 1] = { ":", hl("TelescopeResultsComment", "Comment") }
    chunks[#chunks + 1] = { tostring(item.display_col), hl("TelescopeResultsNumber", "Number") }
  end

  return displayer(chunks)
end

---Pick a location using Telescope
---@param locations PeekstackLocation[]
---@param opts? table
---@param cb fun(location: PeekstackLocation)
function M.pick(locations, opts, cb)
  local ok, telescope = pcall(require, "telescope.pickers")
  if not ok then
    vim.notify("telescope not available", vim.log.levels.WARN)
    return
  end
  local finders = require("telescope.finders")
  local entry_display = require("telescope.pickers.entry_display")
  local conf = require("telescope.config").values
  local telescope_opts = opts or {}
  local displayer = entry_display.create({
    separator = "",
    items = {
      { remaining = true },
    },
  })

  local items = picker_util.build_external_items(locations, 1)
  local entries = {}
  for _, item in ipairs(items) do
    table.insert(entries, {
      value = item.value,
      display = function()
        return display_entry(displayer, item)
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
        map("i", "<CR>", function(bufnr)
          local selection = require("telescope.actions.state").get_selected_entry()
          require("telescope.actions").close(bufnr)
          if selection and selection.value then
            cb(selection.value)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
