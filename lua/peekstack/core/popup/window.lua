local notify = require("peekstack.util.notify")
local render = require("peekstack.ui.render")

local M = {}

---@param winid integer
---@param location PeekstackLocation
---@param line_offset? integer lines skipped from the start of the source buffer
local function set_cursor(winid, location, line_offset)
  local line = (location.range.start.line or 0) + 1 - (line_offset or 0)
  local col = location.range.start.character or 0
  pcall(vim.api.nvim_win_set_cursor, winid, { math.max(1, line), col })
end

---@param winid integer
---@param win_opts PeekstackRenderWinOpts
---@param opts table
---@return string?, PeekstackTitleChunk[]?
local function resolve_title(winid, win_opts, opts)
  local title = nil
  local title_chunks = nil
  if win_opts.title ~= nil then
    if type(win_opts.title) == "table" then
      title_chunks = win_opts.title
    end
    title = render.title_text(win_opts.title)
    if title == "" then
      title = nil
      title_chunks = nil
    end
  end

  if opts.title and opts.title ~= "" then
    win_opts.title = opts.title
    win_opts.title_pos = "center"
    pcall(vim.api.nvim_win_set_config, winid, win_opts)
    title = render.title_text(opts.title)
    title_chunks = nil
    if title == "" then
      title = nil
    end
  end

  return title, title_chunks
end

---@param bufnr integer
---@param location PeekstackLocation
---@param opts table
---@param line_offset integer
---@return { winid: integer, win_opts: PeekstackRenderWinOpts, title: string?, title_chunks: PeekstackTitleChunk[]? }?
function M.open(bufnr, location, opts, line_offset)
  local ok_win, winid, win_opts = pcall(render.open, bufnr, location, opts)
  if not ok_win or not winid then
    notify.warn("Failed to open popup window")
    return nil
  end

  local title, title_chunks = resolve_title(winid, win_opts, opts)
  set_cursor(winid, location, line_offset)

  return {
    winid = winid,
    win_opts = win_opts,
    title = title,
    title_chunks = title_chunks,
  }
end

return M
