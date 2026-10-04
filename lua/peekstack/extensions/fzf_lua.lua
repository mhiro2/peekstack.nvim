local ext = require("peekstack.extensions")
local notify = require("peekstack.util.notify")

local M = {}

---@param value integer?
---@return integer?
local function positive(value)
  return value and value > 0 and value or nil
end

---Push the selected fzf-lua entry onto the stack.
---`fzf_opts` are the picker opts fzf-lua passes to the action; they carry the
---picker cwd that relative entries are resolved against.
---@param selected string[]
---@param fzf_opts? table
---@param push_opts? { provider?: string, mode?: string }
local function push_action(selected, fzf_opts, push_opts)
  if not selected or not selected[1] then
    return
  end
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    return
  end
  local entry = fzf.path.entry_to_file(selected[1], fzf_opts)
  if entry then
    -- fzf-lua reports 0 for a missing line or column.
    ext.push_entry({
      filename = entry.path,
      lnum = positive(entry.line),
      col = positive(entry.col),
    }, push_opts)
  end
end

---@param fzf_picker string
---@param provider string
---@param opts? table
local function open_picker(fzf_picker, provider, opts)
  opts = opts or {}
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    notify.warn("fzf-lua not available")
    return
  end
  local fn = fzf[fzf_picker]
  if not fn then
    notify.warn("fzf-lua." .. fzf_picker .. " not found")
    return
  end

  local push_opts = { provider = provider, mode = opts.mode }
  -- Replace only the confirm action so the caller's other actions keep working.
  -- fzf-lua maps "default" to "enter" and lets it win over an "enter" entry.
  local confirm = {
    ["default"] = function(selected, picker_opts)
      push_action(selected, picker_opts, push_opts)
    end,
  }
  local user_actions = opts.actions
  local actions
  if type(user_actions) == "function" then
    -- fzf-lua also accepts actions as a function of the picker opts.
    actions = function(...)
      return vim.tbl_extend("force", user_actions(...) or {}, confirm)
    end
  else
    actions = vim.tbl_extend("force", user_actions or {}, confirm)
  end
  local fzf_opts = vim.tbl_extend("force", opts, { actions = actions })
  fzf_opts.mode = nil

  fn(fzf_opts)
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
