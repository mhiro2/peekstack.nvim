local config = require("peekstack.config")
local layout = require("peekstack.core.layout")
local fs = require("peekstack.util.fs")
local str = require("peekstack.util.str")
local treesitter = require("peekstack.util.treesitter")

local M = {}

---Get treesitter context for a location if enabled
---@param location PeekstackLocation
---@param ui_config table
---@return string
local function get_treesitter_context(location, ui_config)
  local context_cfg = ui_config.title.context
  if not context_cfg or not context_cfg.enabled then
    return ""
  end

  local fname = fs.uri_to_fname(location.uri)
  local bufnr = vim.fn.bufnr(fname)
  if not bufnr or bufnr == -1 or not vim.api.nvim_buf_is_valid(bufnr) then
    return ""
  end

  local ctx =
    treesitter.context_at(bufnr, location.range.start.line or 0, location.range.start.character or 0, context_cfg)

  if not ctx or ctx == "" then
    return ""
  end

  local separator = context_cfg.separator or " • "
  return separator .. ctx
end

---@type table<integer, string>
local severity_labels = {
  [1] = "[Error] ",
  [2] = "[Warn] ",
  [3] = "[Info] ",
  [4] = "[Hint] ",
}

---Build the title string for a popup window
---@param location PeekstackLocation
---@return string?
local function build_title(location)
  local ui = config.get().ui
  if not ui.title.enabled then
    return nil
  end

  local provider_name = location.provider or ""
  local is_diagnostic = provider_name:match("^diagnostics%.") ~= nil

  local path = str.shorten_path(fs.uri_to_fname(location.uri))
  local use_breadcrumbs = ui.title.breadcrumbs
  if is_diagnostic then
    use_breadcrumbs = false
  end
  if use_breadcrumbs then
    path = str.breadcrumb_path(path)
  end
  local path_max_width = ui.path and ui.path.max_width
  if is_diagnostic and type(path_max_width) == "number" and path_max_width > 0 then
    path = str.truncate_middle(path, path_max_width)
  end
  local line = (location.range.start.line or 0) + 1
  local context = get_treesitter_context(location, ui)

  local kind = ""
  if type(location.kind) == "number" then
    kind = severity_labels[location.kind] or ""
  end

  local text = location.text or ""
  if text ~= "" then
    text = text:gsub("%s+", " ")
    text = vim.trim(text)
  end

  local provider = provider_name
  local format = ui.title.format or ""
  if is_diagnostic and text ~= "" then
    if not format:find("{text}", 1, true) then
      provider = text
    end
  end

  return str.format_title(format, {
    provider = provider,
    path = path,
    line = line,
    context = context,
    kind = kind,
    text = text,
  })
end

---Open a popup window for a location
---@param bufnr integer
---@param location PeekstackLocation
---@param opts? { buffer_mode?: "copy"|"source" }
---@return integer winid
---@return table win_opts
function M.open(bufnr, location, opts)
  local layout_opts = layout.compute(1)
  local win_opts = {
    relative = "editor",
    row = layout_opts.row,
    col = layout_opts.col,
    width = layout_opts.width,
    height = layout_opts.height,
    style = "minimal",
    border = "rounded",
    focusable = true,
    zindex = layout_opts.zindex,
  }

  local title = build_title(location)
  if title and title ~= "" then
    win_opts.title = title
    win_opts.title_pos = "center"
  end

  local winid = vim.api.nvim_open_win(bufnr, true, win_opts)
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = true
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].foldcolumn = "0"
  vim.wo[winid].spell = false
  vim.wo[winid].list = false
  if not opts or opts.buffer_mode ~= "source" then
    vim.bo[bufnr].buflisted = false
  end

  return winid, win_opts
end

return M
