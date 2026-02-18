local ext = require("peekstack.extensions")

local M = {}

---@param item table
---@param opts? table
local function push_from_snacks(item, opts)
  if not item then
    return
  end
  local filename = item.file
  if filename and item.cwd and vim.fn.fnamemodify(filename, ":p") ~= filename then
    filename = item.cwd .. "/" .. filename
  end
  -- snacks pos is {1-based line, 0-based col}; push_entry expects 1-based col
  local col = item.pos and (item.pos[2] + 1) or nil
  ext.push_entry({
    filename = filename,
    lnum = item.pos and item.pos[1],
    col = col,
  }, opts)
end

---@param snacks_picker string
---@param provider string
---@param opts? table
local function open_picker(snacks_picker, provider, opts)
  opts = opts or {}
  local ok, snacks = pcall(require, "snacks.picker")
  if not ok then
    vim.notify("snacks.nvim not available", vim.log.levels.WARN)
    return
  end
  local fn = snacks[snacks_picker]
  if not fn then
    vim.notify("snacks.picker." .. snacks_picker .. " not found", vim.log.levels.WARN)
    return
  end

  local push_opts = { provider = provider, mode = opts.mode }

  fn(vim.tbl_extend("force", opts, {
    confirm = function(picker, item)
      picker:close()
      push_from_snacks(item, push_opts)
    end,
  }))
end

function M.push_file(opts)
  open_picker("files", "extension.file", opts)
end

function M.push_grep(opts)
  open_picker("grep", "extension.grep", opts)
end

function M.push_lsp_references(opts)
  open_picker("lsp_references", "extension.lsp_references", opts)
end

--- Generic action for use in custom snacks picker configurations.
---@param picker table
---@param item table
---@param opts? { provider?: string, mode?: string }
local function push_action(picker, item, opts)
  picker:close()
  push_from_snacks(item, opts)
end

M.actions = { push = push_action }

return M
