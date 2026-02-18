local ext = require("peekstack.extensions")

local M = {}

---@param selected string[]
---@param opts? table
local function push_action(selected, opts)
  if not selected or not selected[1] then
    return
  end
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    return
  end
  local entry = fzf.path.entry_to_file(selected[1])
  if entry then
    ext.push_entry({
      filename = entry.path,
      lnum = entry.line,
      col = entry.col,
    }, opts)
  end
end

---@param fzf_picker string
---@param provider string
---@param opts? table
local function open_picker(fzf_picker, provider, opts)
  opts = opts or {}
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua not available", vim.log.levels.WARN)
    return
  end
  local fn = fzf[fzf_picker]
  if not fn then
    vim.notify("fzf-lua." .. fzf_picker .. " not found", vim.log.levels.WARN)
    return
  end

  local push_opts = { provider = provider, mode = opts.mode }

  fn(vim.tbl_extend("force", opts, {
    actions = {
      ["default"] = function(selected)
        push_action(selected, push_opts)
      end,
    },
  }))
end

function M.push_file(opts)
  open_picker("files", "extension.file", opts)
end

function M.push_grep(opts)
  open_picker("live_grep", "extension.grep", opts)
end

function M.push_lsp_references(opts)
  open_picker("lsp_references", "extension.lsp_references", opts)
end

M.actions = { push = push_action }

return M
