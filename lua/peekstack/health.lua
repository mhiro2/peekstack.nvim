local M = {}

---@type table<string, string>
local PICKER_MODULES = {
  telescope = "telescope.pickers",
  ["fzf-lua"] = "fzf-lua",
  snacks = "snacks.picker",
}

local function report_environment()
  if vim.fn.has("nvim-0.12") == 1 then
    vim.health.ok("nvim >= 0.12")
  else
    vim.health.error("nvim >= 0.12 is required")
  end

  if vim.fn.executable("rg") == 1 then
    vim.health.ok("rg available")
  else
    vim.health.warn("rg not found (grep.search will be unavailable)")
  end
end

---@param cfg PeekstackConfig
local function report_providers(cfg)
  ---@type { name: string, enabled: boolean, note: string? }[]
  local entries = {
    { name = "lsp", enabled = cfg.providers.lsp.enable },
    { name = "diagnostics", enabled = cfg.providers.diagnostics.enable },
    { name = "file", enabled = cfg.providers.file.enable },
    { name = "grep", enabled = true, note = "always registered" },
    { name = "marks", enabled = cfg.providers.marks.enable },
  }

  ---@type string[]
  local enabled_names = {}
  for _, entry in ipairs(entries) do
    if entry.enabled then
      enabled_names[#enabled_names + 1] = entry.name
    end
  end

  if #enabled_names == 0 then
    vim.health.warn("providers: none enabled")
  else
    vim.health.ok("providers enabled: " .. table.concat(enabled_names, ", "))
  end

  for _, entry in ipairs(entries) do
    if not entry.enabled then
      vim.health.info(string.format("provider '%s' disabled", entry.name))
    elseif entry.note then
      vim.health.info(string.format("provider '%s' (%s)", entry.name, entry.note))
    end
  end
end

---@param cfg PeekstackConfig
local function report_picker(cfg)
  local backend = cfg.picker and cfg.picker.backend or "builtin"
  if backend == "builtin" then
    vim.health.ok("picker backend 'builtin'")
  else
    local plugin_name = PICKER_MODULES[backend]
    if plugin_name then
      local installed = pcall(require, plugin_name)
      if installed then
        vim.health.ok("picker backend '" .. backend .. "' available")
      else
        vim.health.warn("picker backend '" .. backend .. "' is configured but the plugin is not installed")
      end
    else
      vim.health.warn("unknown picker backend '" .. backend .. "'")
    end
  end

  if cfg.picker and cfg.picker.builtin and cfg.picker.builtin.preview_lines ~= nil then
    vim.health.info(string.format("picker.builtin.preview_lines = %d", cfg.picker.builtin.preview_lines))
  end
end

---@param cfg PeekstackConfig
local function report_persist(cfg)
  local persist = cfg.persist
  if not persist or not persist.enabled then
    vim.health.info("persist disabled")
    return
  end

  vim.health.ok("persist enabled (max_items=" .. tostring(persist.max_items) .. ")")

  local has_repo = true
  local ok_fs, fs = pcall(require, "peekstack.util.fs")
  if ok_fs then
    local ok_path, path = pcall(fs.scope_path, "repo")
    if ok_path and path then
      vim.health.info("storage path: " .. path)
    end
    has_repo = fs.repo_root() ~= nil
    if not has_repo then
      vim.health.warn("not inside a git repository; sessions fall back to cwd-based storage")
    end
  end

  if type(persist.auto) ~= "table" then
    vim.health.info("auto persist disabled")
    return
  end

  if not persist.auto.enabled then
    vim.health.info("auto persist disabled")
    return
  end

  local message = string.format(
    "auto persist enabled (session=%q, debounce_ms=%d, save_on_leave=%s)",
    tostring(persist.auto.session_name),
    persist.auto.debounce_ms or 0,
    tostring(persist.auto.save_on_leave)
  )
  if has_repo then
    vim.health.ok(message)
  else
    vim.health.warn(message .. "; inactive outside git repository")
  end
end

---@param events string[]?
---@return string
local function format_events(events)
  if not events or #events == 0 then
    return "(none)"
  end
  return table.concat(events, ", ")
end

---@param cfg PeekstackConfig
local function report_close_events(cfg)
  local quick = cfg.ui and cfg.ui.quick_peek and cfg.ui.quick_peek.close_events
  vim.health.info("quick_peek close_events: " .. format_events(quick))

  local inline = cfg.ui and cfg.ui.inline_preview and cfg.ui.inline_preview.close_events
  if cfg.ui and cfg.ui.inline_preview and cfg.ui.inline_preview.enabled then
    vim.health.info("inline_preview close_events: " .. format_events(inline))
  else
    vim.health.info("inline_preview disabled")
  end
end

---@param cfg PeekstackConfig
local function report_treesitter(cfg)
  local context = cfg.ui and cfg.ui.title and cfg.ui.title.context
  if not context or not context.enabled then
    vim.health.info("title context disabled (ui.title.context.enabled = false)")
    return
  end

  vim.health.ok(string.format("title context enabled (max_depth=%d)", context.max_depth or 0))

  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  local label = filetype ~= "" and string.format("filetype=%q", filetype) or "no filetype"

  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr)
  if ok_parser and parser then
    vim.health.ok("tree-sitter parser available for current buffer (" .. label .. ")")
  else
    vim.health.info("tree-sitter context enabled but no parser for the current buffer (" .. label .. ")")
  end
end

function M.check()
  vim.health.start("peekstack")

  report_environment()

  local ok, cfg_mod = pcall(require, "peekstack.config")
  if not ok then
    vim.health.error("peekstack.config could not be loaded")
    return
  end
  local cfg = cfg_mod.get()

  report_providers(cfg)
  report_picker(cfg)
  report_persist(cfg)
  report_close_events(cfg)
  report_treesitter(cfg)
end

return M
