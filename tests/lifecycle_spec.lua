-- Popup lifecycle through real autocmds: setup -> create -> switch -> close.
local stack = require("peekstack.core.stack")
local config = require("peekstack.config")
local events = require("peekstack.core.events")
local helpers = require("tests.helpers")

---@param patterns string[]
---@return table<string, integer[]> received popup ids per event
---@return integer group
local function record_events(patterns)
  local received = {}
  for _, pattern in ipairs(patterns) do
    received[pattern] = {}
  end
  local group = vim.api.nvim_create_augroup("PeekstackLifecycleSpec", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = patterns,
    callback = function(args)
      table.insert(received[args.match], args.data and args.data.popup_id)
    end,
  })
  return received, group
end

---@return integer[]
local function floating_wins()
  local wins = {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(winid).relative ~= "" then
      table.insert(wins, winid)
    end
  end
  return wins
end

local function close_floats()
  for _, winid in ipairs(floating_wins()) do
    pcall(vim.api.nvim_win_close, winid, true)
  end
end

describe("popup lifecycle", function()
  before_each(function()
    stack._reset()
    config.setup({
      ui = {
        quick_peek = { close_events = { "InsertEnter" } },
        popup = { auto_close = { enabled = false } },
      },
    })
    events.setup()
  end)

  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "PeekstackLifecycleSpec")
    close_floats()
    stack._reset()
  end)

  describe("close", function()
    it("emits one close event and history entry per popup on close_all", function()
      local received, group = record_events({ "PeekstackClose", "PeekstackHistoryPush" })
      local ids = {}
      for _ = 1, 3 do
        table.insert(ids, stack.push(helpers.make_location()).id)
      end

      stack.close_all()
      vim.api.nvim_del_augroup_by_id(group)

      table.sort(received.PeekstackClose)
      table.sort(received.PeekstackHistoryPush)
      assert.same(ids, received.PeekstackClose)
      assert.same(ids, received.PeekstackHistoryPush)
      assert.equals(3, #stack.history_list())
      assert.equals(0, #floating_wins())
    end)

    it("emits one close event when a single popup is closed", function()
      local received, group = record_events({ "PeekstackClose" })
      local model = stack.push(helpers.make_location())

      stack.close(model.id)
      vim.api.nvim_del_augroup_by_id(group)

      assert.same({ model.id }, received.PeekstackClose)
      assert.equals(1, #stack.history_list())
    end)

    it("records an externally closed popup once and keeps it restorable", function()
      local received, group = record_events({ "PeekstackClose", "PeekstackHistoryPush" })
      local first = stack.push(helpers.make_location())
      local second = stack.push(helpers.make_location())

      vim.api.nvim_win_close(second.winid, true)
      vim.api.nvim_del_augroup_by_id(group)

      assert.same({ second.id }, received.PeekstackClose)
      assert.same({ second.id }, received.PeekstackHistoryPush)
      assert.same({ first }, stack.list())
      assert.equals(first.id, stack.focused_id())

      local restored = stack.restore_last()
      assert.is_not_nil(restored)
      assert.equals(2, #stack.list())
    end)

    it("survives popups removed by a nested wipe while closing all", function()
      local path = vim.fn.tempname() .. ".txt"
      vim.fn.writefile({ "origin" }, path)
      local root = vim.api.nvim_get_current_win()
      local previous = vim.api.nvim_win_get_buf(root)
      local origin_bufnr = vim.fn.bufadd(path)
      vim.fn.bufload(origin_bufnr)
      vim.bo[origin_bufnr].bufhidden = "wipe"
      vim.api.nvim_win_set_buf(root, origin_bufnr)

      local location = helpers.make_location({ uri = vim.uri_from_bufnr(origin_bufnr) })
      local copy = stack.push(location)
      vim.api.nvim_set_current_win(root)
      local source = stack.push(location, { buffer_mode = "source" })
      vim.api.nvim_set_current_win(root)
      -- The source popup keeps the origin buffer displayed, so it survives this.
      vim.api.nvim_win_set_buf(root, previous)
      assert.is_true(vim.api.nvim_buf_is_valid(origin_bufnr))

      local received, group = record_events({ "PeekstackClose" })
      assert.has_no.errors(function()
        stack.close_all()
      end)
      vim.api.nvim_del_augroup_by_id(group)
      vim.fn.delete(path)

      table.sort(received.PeekstackClose)
      assert.same({ copy.id, source.id }, received.PeekstackClose)
      assert.equals(0, #stack.list())
      assert.equals(0, #floating_wins())
    end)

    it("releases a source quick peek closed from outside", function()
      local received, group = record_events({ "PeekstackClose" })
      local model = stack.push(
        helpers.make_location({
          provider = "diagnostics.under_cursor",
          text = "external close",
        }),
        { stack = false, buffer_mode = "source" }
      )
      assert.is_not_nil(model)
      local ns = vim.api.nvim_get_namespaces().peekstack_diagnostics
      assert.is_true(#vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, {}) > 0)

      vim.api.nvim_win_close(model.winid, true)
      vim.api.nvim_del_augroup_by_id(group)

      assert.is_nil(stack._ephemerals()[model.id])
      assert.is_nil(stack.find_by_id(model.id))
      assert.equals(0, #vim.api.nvim_buf_get_extmarks(model.bufnr, ns, 0, -1, {}))
      assert.same({ model.id }, received.PeekstackClose)
    end)
  end)

  describe("cleanup after the parent popup closes", function()
    local cleanup = require("peekstack.core.cleanup")

    ---@param child_opts? table
    ---@return PeekstackPopupModel parent, PeekstackPopupModel child
    local function push_parent_and_child(child_opts)
      local location = helpers.make_location()
      local parent = stack.push(location)
      vim.api.nvim_set_current_win(parent.winid)
      local child = stack.push(location, child_opts)
      assert.equals(parent.id, child.parent_popup_id)
      assert.is_true(child.origin_is_popup)
      stack.close(parent.id)
      assert.is_false(vim.api.nvim_buf_is_valid(child.origin.bufnr))
      return parent, child
    end

    before_each(function()
      config.setup({
        ui = {
          quick_peek = { close_events = { "InsertEnter" } },
          popup = {
            auto_close = { enabled = true, idle_ms = 300000, check_interval_ms = 60000, ignore_pinned = true },
          },
        },
      })
      events.setup()
    end)

    after_each(function()
      cleanup.stop()
    end)

    it("keeps a child that is still within the idle threshold", function()
      local _, child = push_parent_and_child()
      cleanup.scan(vim.uv.now())
      assert.is_not_nil(stack.find_by_id(child.id))
    end)

    it("keeps a pinned child", function()
      local _, child = push_parent_and_child()
      stack.toggle_pin_by_id(child.id)
      cleanup.scan(vim.uv.now() + 600000)
      assert.is_not_nil(stack.find_by_id(child.id))
    end)

    it("keeps a child whose source buffer is modified", function()
      local _, child = push_parent_and_child({ buffer_mode = "source" })
      vim.bo[child.bufnr].modified = true
      cleanup.scan(vim.uv.now() + 600000)
      assert.is_not_nil(stack.find_by_id(child.id))
      vim.bo[child.bufnr].modified = false
    end)

    it("still closes a popup whose origin buffer was wiped", function()
      local scratch = vim.api.nvim_create_buf(true, true)
      local root = vim.api.nvim_get_current_win()
      local previous = vim.api.nvim_win_get_buf(root)
      vim.api.nvim_win_set_buf(root, scratch)
      local model = stack.push(helpers.make_location({ uri = vim.uri_from_bufnr(previous) }))
      vim.api.nvim_set_current_win(root)
      vim.api.nvim_win_set_buf(root, previous)
      -- Wipe without the BufWipeout handler so the periodic scan has to catch it.
      vim.api.nvim_cmd({ cmd = "bwipeout", args = { tostring(scratch) }, mods = { noautocmd = true } }, {})

      cleanup.scan(vim.uv.now())
      assert.is_nil(stack.find_by_id(model.id))
    end)
  end)

  describe("hidden stack", function()
    ---Every floating window belongs to a popup in the stack.
    local function assert_all_floats_tracked()
      local tracked = {}
      for _, item in ipairs(stack.list()) do
        assert.is_not_nil(item.winid)
        tracked[item.winid] = true
      end
      local floats = floating_wins()
      for _, winid in ipairs(floats) do
        assert.is_true(tracked[winid] == true, "untracked float " .. winid)
      end
      assert.equals(#stack.list(), #floats)
    end

    local function assert_close_all_closes_everything()
      stack.close_all()
      assert.equals(0, #floating_wins())
    end

    ---@param restore fun()
    local function restore_while_hidden(restore)
      local first = stack.push(helpers.make_location())
      local second = stack.push(helpers.make_location())
      stack.close(second.id)
      stack.toggle()
      assert.is_true(stack.is_hidden())

      restore()
      assert.is_false(stack.is_hidden())
      assert_all_floats_tracked()

      stack.toggle()
      stack.toggle()
      assert_all_floats_tracked()
      assert.equals(first.id, stack.list()[1].id)
      assert_close_all_closes_everything()
    end

    it("shows the stack when restore_last runs while hidden", function()
      restore_while_hidden(function()
        assert.is_not_nil(stack.restore_last())
      end)
    end)

    it("shows the stack when restore_all runs while hidden", function()
      restore_while_hidden(function()
        assert.equals(1, #stack.restore_all())
      end)
    end)

    it("shows the stack when restore_from_history runs while hidden", function()
      restore_while_hidden(function()
        assert.is_not_nil(stack.restore_from_history(1))
      end)
    end)

    it("shows the stack when a popup is focused while hidden", function()
      local first = stack.push(helpers.make_location())
      stack.push(helpers.make_location())
      stack.toggle()

      assert.is_true(stack.focus_by_id(first.id))
      assert.is_false(stack.is_hidden())
      assert.equals(stack.find_by_id(first.id).winid, vim.api.nvim_get_current_win())
      assert_all_floats_tracked()

      stack.toggle()
      stack.toggle()
      assert_all_floats_tracked()
      assert_close_all_closes_everything()
    end)

    it("does not open a second window for a popup that is already shown", function()
      local model = stack.push(helpers.make_location())
      assert.equals(model, stack.reopen_by_id(model.id))
      assert_all_floats_tracked()
    end)
  end)

  describe("restore_all", function()
    ---@return PeekstackPopupModel parent, PeekstackPopupModel child
    local function push_parent_and_child()
      local location = helpers.make_location()
      local parent = stack.push(location)
      vim.api.nvim_set_current_win(parent.winid)
      local child = stack.push(location)
      assert.equals(parent.id, child.parent_popup_id)
      return parent, child
    end

    ---@param restored PeekstackPopupModel[]
    ---@param parent_id integer old id of the parent
    ---@return PeekstackPopupModel? parent, PeekstackPopupModel? child
    local function split_restored(restored, parent_id)
      local parent, child
      for _, model in ipairs(restored) do
        if model.parent_popup_id ~= nil then
          child = model
        else
          parent = model
        end
      end
      assert.is_not.equals(parent_id, parent and parent.id)
      return parent, child
    end

    it("links the child when the parent was closed first", function()
      local parent, child = push_parent_and_child()
      stack.close(parent.id)
      stack.close(child.id)

      local restored = stack.restore_all()
      assert.equals(2, #restored)
      local new_parent, new_child = split_restored(restored, parent.id)
      assert.is_not_nil(new_parent)
      assert.is_not_nil(new_child)
      assert.equals(new_parent.id, new_child.parent_popup_id)
    end)

    it("links the child when the child was closed first", function()
      local parent, child = push_parent_and_child()
      stack.close(child.id)
      stack.close(parent.id)

      local restored = stack.restore_all()
      local new_parent, new_child = split_restored(restored, parent.id)
      assert.is_not_nil(new_child)
      assert.equals(new_parent.id, new_child.parent_popup_id)
    end)

    it("announces restored popups only after their parents are linked", function()
      local parent, child = push_parent_and_child()
      stack.close(parent.id)
      stack.close(child.id)

      local parent_at_push = {}
      local group = vim.api.nvim_create_augroup("PeekstackLifecycleSpec", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "PeekstackRestorePopup",
        callback = function(args)
          parent_at_push[args.data.popup_id] = stack.find_by_id(args.data.popup_id).parent_popup_id or false
        end,
      })

      local _, new_child = split_restored(stack.restore_all(), parent.id)
      assert.equals(new_child.parent_popup_id, parent_at_push[new_child.id])
    end)

    it("keeps the link around an entry that fails to restore", function()
      local parent, child = push_parent_and_child()
      stack.close(parent.id)
      local broken = { location = { uri = nil }, title = "broken", buffer_mode = "copy" }
      table.insert(stack.history_list(), broken)
      stack.close(child.id)

      local restored = stack.restore_all()
      assert.equals(2, #restored)
      local new_parent, new_child = split_restored(restored, parent.id)
      assert.equals(new_parent.id, new_child.parent_popup_id)
      assert.same({ broken }, stack.history_list())
    end)
  end)

  describe("activity tracking", function()
    local path

    -- A headless test never reaches the main loop, which is where Neovim
    -- fires CursorMoved, so fire it from the popup window after the motion.
    local function move_cursor_down()
      vim.api.nvim_feedkeys("j", "x", false)
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf(), modeline = false })
    end

    before_each(function()
      path = vim.fn.tempname() .. ".txt"
      vim.fn.writefile({ "one", "two", "three", "four" }, path)
    end)

    after_each(function()
      vim.fn.delete(path)
    end)

    it("updates last_active_at when the cursor moves in a new popup", function()
      local model = stack.push(helpers.make_location({ uri = vim.uri_from_fname(path) }))
      assert.equals(model.winid, vim.api.nvim_get_current_win())
      model.last_active_at = 0

      move_cursor_down()

      assert.equals(2, vim.api.nvim_win_get_cursor(model.winid)[1])
      assert.is_true(model.last_active_at > 0)
    end)

    it("keeps a popup in use open across the auto-close scan", function()
      config.setup({
        ui = {
          quick_peek = { close_events = { "InsertEnter" } },
          popup = { auto_close = { enabled = true, idle_ms = 1000, check_interval_ms = 60000 } },
        },
      })
      events.setup()
      local cleanup = require("peekstack.core.cleanup")
      local model = stack.push(helpers.make_location({ uri = vim.uri_from_fname(path) }))
      model.last_active_at = vim.uv.now() - 5000

      move_cursor_down()
      cleanup.scan(vim.uv.now())
      cleanup.stop()

      assert.is_not_nil(stack.find_by_id(model.id))
    end)
  end)
end)
