local M = {}

---@type table<string, string>
local PICKER_MODULES = {
  telescope = "telescope",
  ["fzf-lua"] = "fzf-lua",
  snacks = "snacks",
}

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

  local ok, cfg_mod = pcall(require, "peekstack.config")
  if not ok then
    return
  end
  local cfg = cfg_mod.get()

  -- Picker backend
  local backend = cfg.picker and cfg.picker.backend
  if backend and backend ~= "builtin" then
    local plugin_name = PICKER_MODULES[backend]
    if plugin_name then
      local has = pcall(require, plugin_name)
      if has then
        vim.health.ok("picker backend '" .. backend .. "' available")
      else
        vim.health.warn("picker backend '" .. backend .. "' is configured but the plugin is not installed")
      end
    else
      vim.health.warn("unknown picker backend '" .. backend .. "'")
    end
  end

  -- Persist
  local persist = cfg.persist
  if persist and persist.enabled then
    local fs = require("peekstack.util.fs")
    local repo = fs.repo_root()
    if repo then
      vim.health.ok("persist enabled (repo: " .. repo .. ")")
    else
      vim.health.warn("persist enabled but not inside a git repository; sessions will use cwd-based storage")
    end
    if persist.auto and persist.auto.enabled then
      vim.health.ok("auto persist enabled (session: " .. (persist.auto.session_name or "auto") .. ")")
    end
  end

  -- Tree-sitter context
  local title = cfg.ui and cfg.ui.title
  if title and title.context and title.context.enabled then
    local ts_ok = pcall(vim.treesitter.get_parser, 0)
    if ts_ok then
      vim.health.ok("tree-sitter context enabled (parser available for current buffer)")
    else
      vim.health.info("tree-sitter context enabled but no parser for the current buffer filetype")
    end
  end
end

return M
