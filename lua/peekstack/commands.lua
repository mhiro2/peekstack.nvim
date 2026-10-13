local M = {}
local notify = require("peekstack.util.notify")

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
  "PeekstackToggle",
  "PeekstackZoom",
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
  return vim.fn.strftime("%Y-%m-%d %H:%M:%S", updated_at)
end

---@return string[]
local function list_session_names()
  local persist = require("peekstack.persist")
  local names = vim.tbl_keys(persist.list_sessions())
  table.sort(names)
  return names
end

---Keep only candidates whose prefix matches the current argument.
---Lua command completion behaves like `customlist`, so Neovim does not filter
---the returned list against `ArgLead` for us.
---@param candidates string[]
---@param arg_lead string
---@return string[]
local function filter_by_prefix(candidates, arg_lead)
  if not arg_lead or arg_lead == "" then
    return candidates
  end
  return vim.tbl_filter(function(candidate)
    return vim.startswith(candidate, arg_lead)
  end, candidates)
end

---@param arg_lead string
---@return string[]
local function complete_session_names(arg_lead)
  return filter_by_prefix(list_session_names(), arg_lead)
end

---Storage and stack a session command acts on.
---Prompts and pickers answer asynchronously, and the user may change
---directory or window before they do, so both are fixed when the command
---runs and handed to every later step.
---@class PeekstackSessionCommandTarget
---@field store_path string
---@field root_winid integer

---@return PeekstackSessionCommandTarget
local function capture_session_target()
  return {
    store_path = require("peekstack.persist.orchestrator").store_path(),
    -- The resolved stack root, so closing the popup or stack view the command
    -- ran from does not lose the stack; saves and restores are dropped once
    -- the root window itself is gone.
    root_winid = require("peekstack.persist.sessions").resolve_root_winid() --[[@as integer]],
  }
end

---Confirm and delete a named session.
---@param name string
---@param target PeekstackSessionCommandTarget
local function confirm_delete_session(name, target)
  vim.ui.select({ "Yes", "No" }, { prompt = "Delete session '" .. name .. "'?" }, function(choice)
    if choice == "Yes" then
      require("peekstack.persist").delete_session(name, { store_path = target.store_path })
    end
  end)
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
      local target = capture_session_target()
      vim.ui.input(
        { prompt = "Session name: ", default = cfg.persist.session.default_name or "default" },
        function(input)
          if input and input ~= "" then
            require("peekstack.persist").save_current(input, {
              store_path = target.store_path,
              root_winid = target.root_winid,
            })
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
    complete = complete_session_names,
  })

  vim.api.nvim_create_user_command("PeekstackListSessions", function()
    local persist = require("peekstack.persist")
    local target = capture_session_target()
    persist.list_sessions({
      store_path = target.store_path,
      on_done = function(sessions)
        local names = vim.tbl_keys(sessions)
        table.sort(names)
        if #names == 0 then
          notify.info("No saved sessions")
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
              persist.restore(selected, { store_path = target.store_path, root_winid = target.root_winid })
            end
          end)
        end)
      end,
    })
  end, {})

  vim.api.nvim_create_user_command("PeekstackDeleteSession", function(opts)
    local name = opts.args and opts.args ~= "" and opts.args or nil
    local target = capture_session_target()
    if name then
      confirm_delete_session(name, target)
      return
    end

    require("peekstack.persist").list_sessions({
      store_path = target.store_path,
      on_done = function(sessions)
        local names = vim.tbl_keys(sessions)
        table.sort(names)
        if #names == 0 then
          notify.info("No saved sessions")
          return
        end
        vim.ui.select(names, { prompt = "Delete session" }, function(selected)
          if not selected then
            return
          end
          confirm_delete_session(selected, target)
        end)
      end,
    })
  end, {
    nargs = "?",
    complete = complete_session_names,
  })

  vim.api.nvim_create_user_command("PeekstackRestorePopup", function()
    local restored = require("peekstack.core.stack").restore_last()
    if not restored then
      notify.info("No closed popups to restore")
    end
  end, {})

  vim.api.nvim_create_user_command("PeekstackRestoreAllPopups", function()
    local restored = require("peekstack.core.stack").restore_all()
    if #restored == 0 then
      notify.info("No closed popups to restore")
    end
  end, {})

  vim.api.nvim_create_user_command("PeekstackHistory", function()
    local stack = require("peekstack.core.stack")
    local loc = require("peekstack.core.location")
    local cfg = require("peekstack.config").get()
    local history = stack.history_list()
    if #history == 0 then
      notify.info("No history entries")
      return
    end
    local ui_path = cfg.ui.path or {}
    ---@type PeekstackDisplayTextOpts
    local dt_opts = {
      path_base = ui_path.base,
      max_width = ui_path.max_width,
    }
    local items = {}
    for i = #history, 1, -1 do
      local entry = history[i]
      local label = entry.title or loc.display_text(entry.location, 0, dt_opts)
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

  vim.api.nvim_create_user_command("PeekstackToggle", function()
    local toggled = require("peekstack.core.stack").toggle()
    if not toggled then
      notify.info("No popups in the current stack")
    end
  end, {})

  vim.api.nvim_create_user_command("PeekstackZoom", function()
    local toggled = require("peekstack.core.stack").toggle_zoom()
    if not toggled then
      notify.info("No popups in the current stack")
    end
  end, {})

  vim.api.nvim_create_user_command("PeekstackQuickPeek", function(opts)
    local provider = opts.args and opts.args ~= "" and opts.args or "lsp.definition"
    require("peekstack").peek(provider, { mode = "quick" })
  end, {
    nargs = "?",
    complete = function(arg_lead)
      return filter_by_prefix(require("peekstack").list_providers(), arg_lead)
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
