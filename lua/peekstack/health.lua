local M = {}

function M.check()
  vim.health.start("peekstack")

  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("nvim >= 0.10")
  else
    vim.health.error("nvim >= 0.10 is required (vim.lsp.get_clients, vim.islist, vim.system)")
  end

  if vim.fn.executable("rg") == 1 then
    vim.health.ok("rg available")
  else
    vim.health.warn("rg not found (grep.search will be unavailable)")
  end
end

return M
