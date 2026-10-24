---@type string
local root = vim.fn.getcwd()
---@type string
local plenary = os.getenv("PLENARY_PATH") or (root .. "/deps/plenary.nvim")

-- Give every Neovim process its own state directory. PlenaryBustedDirectory
-- runs each spec file in a separate process, in parallel, and session stores
-- under a shared directory would let one spec overwrite another's fixtures.
-- tempname() lives in this process's temp directory, which Neovim removes
-- when it exits.
---@type string
local tmp_root = vim.fn.tempname()
vim.env.XDG_STATE_HOME = tmp_root .. "/state"
vim.fn.mkdir(vim.env.XDG_STATE_HOME, "p")

-- Options derived from the state directory were set at startup from the one
-- inherited from the parent process, which spec processes running at once
-- would share (and race to create). Point them at this process's own.
---@type string
local swap_dir = vim.env.XDG_STATE_HOME .. "/nvim/swap"
vim.fn.mkdir(swap_dir, "p")
vim.opt.directory = swap_dir .. "//"
---@type string
local undo_dir = vim.env.XDG_STATE_HOME .. "/nvim/undo"
vim.fn.mkdir(undo_dir, "p")
vim.opt.undodir = undo_dir .. "//"

-- Neovim reports an inaccessible log file through vim.notify shortly after
-- startup, which tests asserting on notifications would pick up. The log
-- file is chosen at startup, so this cannot help the current process; it
-- points the spec processes started from here at a writable file.
vim.env.NVIM_LOG_FILE = tmp_root .. "/nvim.log"
-- Set by Neovim when it fell back from an inaccessible log file, so that
-- child processes retry that file first; drop it so they use the one above.
vim.env.__NVIM_LOG_FILE_WANT = nil

vim.g.did_load_ftplugin = 1
vim.api.nvim_cmd({ cmd = "filetype", args = { "plugin", "off" } }, {})

-- Disable ShaDa file to prevent test warnings
vim.opt.shadafile = "NONE"

vim.opt.runtimepath = vim.env.VIMRUNTIME
vim.opt.runtimepath:append(root)
vim.opt.runtimepath:append(plenary)
vim.opt.packpath = vim.opt.runtimepath:get()

vim.api.nvim_cmd({ cmd = "runtime", args = { "plugin/plenary.vim" } }, {})
