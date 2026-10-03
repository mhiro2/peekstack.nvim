local codec = require("peekstack.persist.codec")
local notify = require("peekstack.util.notify")

local M = {}

local write_counter = 0

---@param path string
---@return string
local function next_tmp_path(path)
  write_counter = write_counter + 1
  return string.format("%s.%d.%d.tmp", path, vim.uv.hrtime(), write_counter)
end

---@param path string
---@return boolean
local function ensure_parent_dir(path)
  local dir = vim.fs.dirname(path)
  if vim.uv.fs_stat(dir) then
    return true
  end

  local mkdir_ok = pcall(vim.fn.mkdir, dir, "p")
  if not mkdir_ok then
    notify.warn("Failed to create directory: " .. dir)
    return false
  end

  return true
end

local READ_CHUNK_SIZE = 64 * 1024

---Turn the outcome of reading the store file into store data.
---A missing file is an empty store, but any other I/O error or undecodable
---content yields nil so callers never overwrite data they could not read.
---@param path string
---@param err string? libuv error message
---@param content string?
---@return PeekstackStoreData?
local function resolve_read(path, err, content)
  if err then
    if vim.startswith(err, "ENOENT") then
      return codec.empty_data()
    end
    notify.warn(string.format("Failed to read session data: %s (%s)", path, err))
    return nil
  end
  return codec.decode(path, content or "")
end

---Read the store file until EOF on a single descriptor, so a file replaced by
---an atomic rename is never read as a mix of old size and new content.
---@param path string store file path, resolved by the caller
---@param opts { on_done: fun(data: PeekstackStoreData?) } `data` is nil when the store could not be read
function M.read(path, opts)
  local on_done = opts and opts.on_done or nil
  if not on_done then
    return
  end

  ---@param err string?
  ---@param content string?
  local function finish(err, content)
    vim.schedule(function()
      on_done(resolve_read(path, err, content))
    end)
  end

  vim.uv.fs_open(path, "r", 438, function(open_err, fd)
    if not fd then
      finish(open_err or "open failed")
      return
    end

    local chunks = {}
    local offset = 0
    local function read_next()
      vim.uv.fs_read(fd, READ_CHUNK_SIZE, offset, function(read_err, chunk)
        if read_err or not chunk then
          vim.uv.fs_close(fd)
          finish(read_err or "read failed")
        elseif chunk == "" then
          vim.uv.fs_close(fd)
          finish(nil, table.concat(chunks))
        else
          chunks[#chunks + 1] = chunk
          offset = offset + #chunk
          read_next()
        end
      end)
    end
    read_next()
  end)
end

---@param path string store file path, resolved by the caller
---@return PeekstackStoreData? data nil when the store could not be read
function M.read_sync(path)
  local fd, open_err = vim.uv.fs_open(path, "r", 438)
  if not fd then
    return resolve_read(path, open_err or "open failed")
  end

  local chunks = {}
  local offset = 0
  while true do
    local chunk, read_err = vim.uv.fs_read(fd, READ_CHUNK_SIZE, offset)
    if not chunk then
      pcall(vim.uv.fs_close, fd)
      return resolve_read(path, read_err or "read failed")
    end
    if chunk == "" then
      break
    end
    chunks[#chunks + 1] = chunk
    offset = offset + #chunk
  end
  pcall(vim.uv.fs_close, fd)

  return resolve_read(path, nil, table.concat(chunks))
end

---@param path string store file path, resolved by the caller
---@param data PeekstackStoreData
---@param opts? { on_done?: fun(success: boolean) }
function M.write(path, data, opts)
  local on_done = opts and opts.on_done or nil
  local function finish(success)
    if on_done then
      vim.schedule(function()
        on_done(success)
      end)
    end
  end

  local encoded = codec.encode(data)
  if not encoded then
    finish(false)
    return
  end

  if not ensure_parent_dir(path) then
    finish(false)
    return
  end

  local tmp_path = next_tmp_path(path)
  vim.uv.fs_open(tmp_path, "w", 438, function(open_err, fd)
    if open_err or not fd then
      vim.schedule(function()
        notify.warn("Failed to write session data: " .. path)
      end)
      finish(false)
      return
    end
    vim.uv.fs_write(fd, encoded, 0, function(write_err)
      vim.uv.fs_close(fd, function()
        if write_err then
          vim.schedule(function()
            notify.warn("Failed to write session data: " .. path)
          end)
          pcall(vim.uv.fs_unlink, tmp_path)
          finish(false)
          return
        end
        vim.uv.fs_rename(tmp_path, path, function(rename_err)
          if rename_err then
            vim.schedule(function()
              notify.warn("Failed to write session data: " .. path)
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

---@param path string store file path, resolved by the caller
---@param data PeekstackStoreData
---@return boolean
function M.write_sync(path, data)
  local encoded = codec.encode(data)
  if not encoded then
    return false
  end

  if not ensure_parent_dir(path) then
    return false
  end

  local tmp_path = next_tmp_path(path)
  local fd = vim.uv.fs_open(tmp_path, "w", 438)
  if not fd then
    notify.warn("Failed to write session data: " .. path)
    return false
  end

  local write_ok = vim.uv.fs_write(fd, encoded, 0)
  pcall(vim.uv.fs_close, fd)
  if not write_ok then
    notify.warn("Failed to write session data: " .. path)
    pcall(vim.uv.fs_unlink, tmp_path)
    return false
  end

  local rename_ok = vim.uv.fs_rename(tmp_path, path)
  if not rename_ok then
    notify.warn("Failed to write session data: " .. path)
    pcall(vim.uv.fs_unlink, tmp_path)
    return false
  end

  return true
end

return M
