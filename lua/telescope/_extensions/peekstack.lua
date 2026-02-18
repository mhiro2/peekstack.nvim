local ext = require("peekstack.extensions")

---@param entry table
---@param opts? table
local function push_from_telescope(entry, opts)
  if not entry then
    return
  end
  ext.push_entry({
    filename = entry.path or entry.filename or entry.value,
    lnum = entry.lnum,
    col = entry.col,
  }, opts)
end

---@param builtin_name string
---@param provider string
---@param opts? table
local function open_builtin(builtin_name, provider, opts)
  opts = opts or {}
  local builtin = require("telescope.builtin")
  local fn = builtin[builtin_name]
  if not fn then
    vim.notify("telescope.builtin." .. builtin_name .. " not found", vim.log.levels.WARN)
    return
  end

  local push_opts = { provider = provider, mode = opts.mode }

  fn(vim.tbl_extend("force", opts, {
    attach_mappings = function(_, map)
      local actions = require("telescope.actions")
      local state = require("telescope.actions.state")
      local function on_select(prompt_bufnr)
        local entry = state.get_selected_entry()
        actions.close(prompt_bufnr)
        push_from_telescope(entry, push_opts)
      end
      map("i", "<CR>", on_select)
      map("n", "<CR>", on_select)
      return true
    end,
  }))
end

--- Generic action for use in custom telescope mappings.
---@param prompt_bufnr integer
---@param opts? { provider?: string, mode?: string }
local function push_action(prompt_bufnr, opts)
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")
  local entry = state.get_selected_entry()
  actions.close(prompt_bufnr)
  push_from_telescope(entry, opts)
end

return require("telescope").register_extension({
  exports = {
    push_file = function(opts)
      open_builtin("find_files", "extension.file", opts)
    end,
    push_grep = function(opts)
      open_builtin("live_grep", "extension.grep", opts)
    end,
    push_lsp_references = function(opts)
      open_builtin("lsp_references", "extension.lsp_references", opts)
    end,
    actions = {
      push = push_action,
    },
  },
})
