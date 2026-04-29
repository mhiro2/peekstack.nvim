local M = {}

---@type table<string, string>
local HIGHLIGHT_LINKS = {
  PeekstackOrigin = "IncSearch",
  PeekstackStackViewIndex = "LineNr",
  PeekstackStackViewPinned = "DiagnosticWarn",
  PeekstackStackViewTree = "Comment",
  PeekstackStackViewProvider = "Type",
  PeekstackStackViewPath = "Directory",
  PeekstackStackViewFocused = "Type",
  PeekstackStackViewPreview = "Comment",
  PeekstackStackViewFilter = "Search",
  PeekstackStackViewHeader = "Title",
  PeekstackStackViewEmpty = "Comment",
  PeekstackStackViewCursorLine = "CursorLine",
  PeekstackInlinePreview = "Comment",
  PeekstackViewportTruncated = "NonText",
  PeekstackTitleProvider = "Type",
  PeekstackTitlePath = "Directory",
  PeekstackTitleIcon = "Special",
  PeekstackTitleLine = "LineNr",
  PeekstackStackViewIcon = "Special",
  PeekstackStackViewLine = "LineNr",
  PeekstackPopupBorder = "FloatBorder",
  PeekstackPopupBorderFocused = "Function",
  PeekstackPopupBorderZoomed = "WarningMsg",
  PeekstackTitleKindError = "DiagnosticError",
  PeekstackTitleKindWarn = "DiagnosticWarn",
  PeekstackTitleKindInfo = "DiagnosticInfo",
  PeekstackTitleKindHint = "DiagnosticHint",
}

function M.apply()
  for name, link in pairs(HIGHLIGHT_LINKS) do
    vim.api.nvim_set_hl(0, name, { default = true, link = link })
  end
end

return M
