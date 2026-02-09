local picker_util = require("peekstack.util.picker")

local M = {}

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
  local conf = require("telescope.config").values
  local telescope_opts = opts or {}

  local items = picker_util.build_external_items(locations, 1)
  local entries = {}
  for _, item in ipairs(items) do
    table.insert(entries, {
      value = item.value,
      display = item.label,
      ordinal = item.label,
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
