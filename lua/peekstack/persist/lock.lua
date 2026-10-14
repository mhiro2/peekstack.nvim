local fs = require("peekstack.util.fs")
local notify = require("peekstack.util.notify")

---Advisory lock that serializes store updates across Neovim processes.
---The in-process update queue cannot see writes from another Neovim using
---the same store, so each read-modify-write holds `<store>.lock`, created
---with O_EXCL, from before the read until after the write.
local M = {}

---How long to wait for another process to release the lock.
local ACQUIRE_TIMEOUT_MS = 1000
local RETRY_INTERVAL_MS = 5
---A lock whose owner pid cannot be read (it may not be written yet) is only
---treated as left behind once it is older than this.
local STALE_AFTER_S = 10

---Locks this process holds, keyed by lock file path.
---@type table<string, fun()>
local held = {}

---Release every lock this process holds.
function M.release_all()
  for _, release in pairs(held) do
    release()
  end
end

-- An async write cut short by quitting must not leave its lock behind.
vim.api.nvim_create_autocmd("VimLeave", {
  group = vim.api.nvim_create_augroup("PeekstackPersistLock", { clear = true }),
  callback = M.release_all,
})

---@param path string store file path
---@return string
function M.lock_path(path)
  return path .. ".lock"
end

---Identity of a lock file, to tell the file this process created from one
---another process created after taking the lock over as stale.
---@param stat uv.fs_stat.result?
---@return string?
local function identity(stat)
  if not stat then
    return nil
  end
  return string.format("%d:%d:%d:%d", stat.dev, stat.ino, stat.mtime.sec, stat.mtime.nsec)
end

---@param lock string
---@param id string
---@return fun() release
local function make_release(lock, id)
  local released = false
  local function release()
    if released then
      return
    end
    released = true
    held[lock] = nil
    if identity(vim.uv.fs_stat(lock)) == id then
      vim.uv.fs_unlink(lock)
    end
  end
  held[lock] = release
  return release
end

---@param lock string
---@return integer?
local function read_pid(lock)
  local fd = vim.uv.fs_open(lock, "r", 438)
  if not fd then
    return nil
  end
  local content = vim.uv.fs_read(fd, 32, 0)
  vim.uv.fs_close(fd)
  return tonumber(content)
end

---Whether the lock was left behind by a process that exited while holding
---it. A lock whose owner is still running is never taken over, however
---long it is held.
---@param lock string
---@param stat uv.fs_stat.result
---@return boolean
local function is_abandoned(lock, stat)
  local pid = read_pid(lock)
  if pid then
    local alive, _, code = vim.uv.kill(pid, 0)
    -- EPERM: the process exists but belongs to another user.
    return not alive and code ~= "EPERM"
  end
  return os.time() - stat.mtime.sec > STALE_AFTER_S
end

---Remove an abandoned lock.
---Takeovers are serialized through `<lock>.takeover`, also created with
---O_EXCL: only the holder of that guard removes a lock it does not own, so
---the lock it checks cannot be replaced before it removes it. Without the
---guard, an instance that found the same abandoned lock could delete the
---lock another one has acquired since.
---@param lock string
---@param stat uv.fs_stat.result the abandoned lock as observed
local function take_over(lock, stat)
  local guard = lock .. ".takeover"
  local fd = vim.uv.fs_open(guard, "wx", 420)
  if not fd then
    -- The guard is held for a stat and an unlink only; one this old was left
    -- by an instance that exited in between. Two instances removing the same
    -- abandoned guard at once could still both end up holding one; that
    -- needs a crash inside that short window and is not guarded against.
    local guard_stat = vim.uv.fs_stat(guard)
    if guard_stat and os.time() - guard_stat.mtime.sec > STALE_AFTER_S then
      vim.uv.fs_unlink(guard)
    end
    return
  end
  vim.uv.fs_close(fd)

  local current = vim.uv.fs_stat(lock)
  if current and identity(current) == identity(stat) and is_abandoned(lock, current) then
    vim.uv.fs_unlink(lock)
  end
  vim.uv.fs_unlink(guard)
end

---Try to take the lock once.
---@param lock string
---@return (fun())? release set when the lock was taken
---@return boolean retry whether another attempt may succeed
local function try_acquire(lock)
  local fd, err, code = vim.uv.fs_open(lock, "wx", 420)
  if fd then
    -- The pid tells other instances whether the owner is still running.
    local written = vim.uv.fs_write(fd, tostring(vim.uv.os_getpid()), 0)
    local id = identity(vim.uv.fs_fstat(fd))
    vim.uv.fs_close(fd)
    if not written or not id then
      vim.uv.fs_unlink(lock)
      notify.warn("Failed to lock session data: " .. lock)
      return nil, false
    end
    return make_release(lock, id), false
  end

  if code == "EEXIST" then
    local stat = vim.uv.fs_stat(lock)
    if stat and is_abandoned(lock, stat) then
      take_over(lock, stat)
    end
    return nil, true
  end
  if code == "ENOENT" then
    local ok = pcall(fs.ensure_dir, vim.fs.dirname(lock))
    if ok then
      return nil, true
    end
  end
  notify.warn(string.format("Failed to lock session data: %s (%s)", lock, tostring(err)))
  return nil, false
end

---@param path string
local function warn_timeout(path)
  notify.warn("Timed out waiting for another Neovim to finish writing session data: " .. path)
end

---Take the lock for the store at `path`, retrying while another process
---holds it. `on_done` receives the release function, or nil when the lock
---could not be taken within ACQUIRE_TIMEOUT_MS.
---@param path string store file path
---@param on_done fun(release: (fun())?)
function M.acquire(path, on_done)
  local lock = M.lock_path(path)
  local deadline = vim.uv.hrtime() + ACQUIRE_TIMEOUT_MS * 1e6
  local function attempt()
    local release, retry = try_acquire(lock)
    if release then
      on_done(release)
      return
    end
    if retry and vim.uv.hrtime() < deadline then
      vim.defer_fn(attempt, RETRY_INTERVAL_MS)
      return
    end
    if retry then
      warn_timeout(path)
    end
    on_done(nil)
  end
  attempt()
end

---Blocking variant of `acquire`. It sleeps between attempts without
---processing events, so no callback can start another update while this
---one waits for the lock.
---@param path string store file path
---@return (fun())? release nil when the lock could not be taken
function M.acquire_sync(path)
  local lock = M.lock_path(path)
  local deadline = vim.uv.hrtime() + ACQUIRE_TIMEOUT_MS * 1e6
  while true do
    local release, retry = try_acquire(lock)
    if release then
      return release
    end
    if not retry then
      return nil
    end
    if vim.uv.hrtime() >= deadline then
      warn_timeout(path)
      return nil
    end
    vim.uv.sleep(RETRY_INTERVAL_MS)
  end
end

return M
