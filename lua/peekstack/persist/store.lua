local fs = require("peekstack.util.fs")

local M = {}

---@return PeekstackStoreData
local function empty_data()
  return { version = 2, sessions = {} }
end

---@param scope string
---@param opts { on_done: fun(data: PeekstackStoreData) }
function M.read(scope, opts)
  local on_done = opts and opts.on_done or nil
  if not on_done then
    return
  end

  local path = fs.scope_path(scope)
  vim.uv.fs_stat(path, function(stat_err, stat)
    if stat_err or not stat or stat.size == 0 then
      vim.schedule(function()
        on_done(empty_data())
      end)
      return
    end

    vim.uv.fs_open(path, "r", 438, function(open_err, fd)
      if open_err or not fd then
        vim.schedule(function()
          on_done(empty_data())
        end)
        return
      end

      vim.uv.fs_read(fd, stat.size, 0, function(read_err, data)
        vim.uv.fs_close(fd)
        if read_err or not data or data == "" then
          vim.schedule(function()
            on_done(empty_data())
          end)
          return
        end
        vim.schedule(function()
          local ok, decoded = pcall(vim.json.decode, data)
          if not ok or type(decoded) ~= "table" then
            on_done(empty_data())
            return
          end
          on_done(decoded)
        end)
      end)
    end)
  end)
end

---@param scope string
---@return PeekstackStoreData
function M.read_sync(scope)
  local path = fs.scope_path(scope)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.size == 0 then
    return empty_data()
  end

  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return empty_data()
  end

  local data = vim.uv.fs_read(fd, stat.size, 0)
  pcall(vim.uv.fs_close, fd)
  if not data or data == "" then
    return empty_data()
  end

  local ok, decoded = pcall(vim.json.decode, data)
  if not ok or type(decoded) ~= "table" then
    return empty_data()
  end
  return decoded
end

---@param scope string
---@param data PeekstackStoreData
---@param opts? { on_done?: fun(success: boolean) }
function M.write(scope, data, opts)
  local on_done = opts and opts.on_done or nil
  local function finish(success)
    if on_done then
      vim.schedule(function()
        on_done(success)
      end)
    end
  end

  local path = fs.scope_path(scope)
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    vim.notify("Failed to encode session data", vim.log.levels.WARN)
    finish(false)
    return
  end
  local dir = vim.fs.dirname(path)
  local dir_stat = vim.uv.fs_stat(dir)
  if not dir_stat then
    local mkdir_ok = pcall(vim.fn.mkdir, dir, "p")
    if not mkdir_ok then
      vim.notify("Failed to create directory: " .. dir, vim.log.levels.WARN)
      finish(false)
      return
    end
  end
  local tmp_path = path .. ".tmp"
  vim.uv.fs_open(tmp_path, "w", 438, function(open_err, fd)
    if open_err or not fd then
      vim.schedule(function()
        vim.notify("Failed to write session data: " .. path, vim.log.levels.WARN)
      end)
      finish(false)
      return
    end
    vim.uv.fs_write(fd, encoded, 0, function(write_err)
      vim.uv.fs_close(fd, function()
        if write_err then
          vim.schedule(function()
            vim.notify("Failed to write session data: " .. path, vim.log.levels.WARN)
          end)
          pcall(vim.uv.fs_unlink, tmp_path)
          finish(false)
          return
        end
        vim.uv.fs_rename(tmp_path, path, function(rename_err)
          if rename_err then
            vim.schedule(function()
              vim.notify("Failed to write session data: " .. path, vim.log.levels.WARN)
            end)
            pcall(vim.uv.fs_unlink, tmp_path)
            finish(false)
            return
          end
          finish(true)
        end)
      end)
    end)
  end)
end

return M
