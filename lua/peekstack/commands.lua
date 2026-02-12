local M = {}

local loaded = false
local COMMAND_NAMES = {
  "PeekstackStack",
  "PeekstackSaveSession",
  "PeekstackRestoreSession",
  "PeekstackListSessions",
  "PeekstackDeleteSession",
  "PeekstackRestorePopup",
  "PeekstackRestoreAllPopups",
  "PeekstackHistory",
  "PeekstackCloseAll",
  "PeekstackQuickPeek",
}

---@param session PeekstackSession|table
---@return integer
local function session_item_count(session)
  local items = session and session.items
  if type(items) ~= "table" then
    return 0
  end
  return #items
end

---@param session PeekstackSession|table
---@return string
local function session_updated_at_text(session)
  local meta = session and session.meta
  local updated_at = type(meta) == "table" and meta.updated_at or nil
  if type(updated_at) ~= "number" then
    return "unknown"
  end
  return os.date("%Y-%m-%d %H:%M:%S", updated_at)
end

---@return string[]
local function list_session_names()
  local persist = require("peekstack.persist")
  local names = vim.tbl_keys(persist.list_sessions())
  table.sort(names)
  return names
end

function M.setup()
  if loaded then
    return
  end
  loaded = true

  vim.api.nvim_create_user_command("PeekstackStack", function()
    require("peekstack.ui.stack_view").open()
  end, {})

  vim.api.nvim_create_user_command("PeekstackSaveSession", function(opts)
    local name = opts.args and opts.args ~= "" and opts.args or nil
    local cfg = require("peekstack.config").get()

    if not name and cfg.persist.session and cfg.persist.session.prompt_if_missing then
      vim.ui.input(
        { prompt = "Session name: ", default = cfg.persist.session.default_name or "default" },
        function(input)
          if input and input ~= "" then
            require("peekstack.persist").save_current(input)
          end
        end
      )
      return
    end

    require("peekstack.persist").save_current(name)
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("PeekstackRestoreSession", function(opts)
    local name = opts.args and opts.args ~= "" and opts.args or nil
    require("peekstack.persist").restore(name)
  end, {
    nargs = "?",
    complete = list_session_names,
  })

  vim.api.nvim_create_user_command("PeekstackListSessions", function()
    local persist = require("peekstack.persist")
    persist.list_sessions({
      on_done = function(sessions)
        local names = vim.tbl_keys(sessions)
        if #names == 0 then
          vim.notify("No saved sessions", vim.log.levels.INFO)
          return
        end
        vim.ui.select(names, { prompt = "Select a session" }, function(selected)
          if not selected then
            return
          end
          local session = sessions[selected]
          local info = string.format(
            "%s: %d items (updated: %s)",
            selected,
            session_item_count(session),
            session_updated_at_text(session)
          )
          vim.ui.select({ "Restore", "Info only" }, { prompt = info }, function(action)
            if action == "Restore" then
              persist.restore(selected)
            end
          end)
        end)
      end,
    })
  end, {})

  vim.api.nvim_create_user_command("PeekstackDeleteSession", function(opts)
    local name = opts.args
    if not name or name == "" then
      vim.notify("Usage: PeekstackDeleteSession <name>", vim.log.levels.WARN)
      return
    end
    vim.ui.select({ "Yes", "No" }, { prompt = "Delete session '" .. name .. "'?" }, function(choice)
      if choice == "Yes" then
        require("peekstack.persist").delete_session(name)
      end
    end)
  end, {
    nargs = 1,
    complete = list_session_names,
  })

  vim.api.nvim_create_user_command("PeekstackRestorePopup", function()
    local restored = require("peekstack.core.stack").restore_last()
    if not restored then
      vim.notify("No closed popups to restore", vim.log.levels.INFO)
    end
  end, {})

  vim.api.nvim_create_user_command("PeekstackRestoreAllPopups", function()
    local restored = require("peekstack.core.stack").restore_all()
    if #restored == 0 then
      vim.notify("No closed popups to restore", vim.log.levels.INFO)
    end
  end, {})

  vim.api.nvim_create_user_command("PeekstackHistory", function()
    local stack = require("peekstack.core.stack")
    local loc = require("peekstack.core.location")
    local history = stack.history_list()
    if #history == 0 then
      vim.notify("No history entries", vim.log.levels.INFO)
      return
    end
    local items = {}
    for i = #history, 1, -1 do
      local entry = history[i]
      local label = entry.title or loc.display_text(entry.location, 0)
      table.insert(items, { idx = i, label = label, entry = entry })
    end
    vim.ui.select(items, {
      prompt = "Popup History",
      format_item = function(item)
        return item.label
      end,
    }, function(selected)
      if not selected then
        return
      end
      stack.restore_from_history(selected.idx)
    end)
  end, {})

  vim.api.nvim_create_user_command("PeekstackCloseAll", function()
    require("peekstack.core.stack").close_all()
  end, {})

  vim.api.nvim_create_user_command("PeekstackQuickPeek", function(opts)
    local provider = opts.args and opts.args ~= "" and opts.args or "lsp.definition"
    require("peekstack").peek(provider, { mode = "quick" })
  end, {
    nargs = "?",
    complete = function()
      return {
        "lsp.definition",
        "lsp.implementation",
        "lsp.references",
        "lsp.type_definition",
        "lsp.declaration",
        "diagnostics.under_cursor",
        "diagnostics.in_buffer",
        "file.under_cursor",
        "grep.search",
        "marks.buffer",
        "marks.global",
        "marks.all",
      }
    end,
  })
end

---Reset command registration state (for tests).
function M._reset()
  loaded = false
  for _, name in ipairs(COMMAND_NAMES) do
    pcall(vim.api.nvim_del_user_command, name)
  end
end

return M
