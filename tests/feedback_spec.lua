describe("peekstack.ui.feedback", function()
  local config = require("peekstack.config")
  local feedback = require("peekstack.ui.feedback")

  before_each(function()
    config.setup({})
  end)

  it("highlights the origin row", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })
    local winid = vim.api.nvim_get_current_win()

    feedback.highlight_origin({ winid = winid, bufnr = bufnr, row = 2, col = 0 })

    local ns = vim.api.nvim_get_namespaces()["peekstack_origin"]
    assert.is_not_nil(ns)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
    assert.equals(1, #marks)
    assert.equals(1, marks[1][2]) -- row 2 (1-based) -> extmark row 1 (0-based)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("does not error when the origin row is beyond the buffer", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "only line" })
    local winid = vim.api.nvim_get_current_win()

    local ok = pcall(feedback.highlight_origin, { winid = winid, bufnr = bufnr, row = 1000, col = 0 })
    assert.is_true(ok)

    -- The row is clamped, so the highlight still lands on the last line.
    local ns = vim.api.nvim_get_namespaces()["peekstack_origin"]
    assert.is_not_nil(ns)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
    assert.equals(1, #marks)
    assert.equals(0, marks[1][2])

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
