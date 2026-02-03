---@type string
local root = vim.fn.getcwd()
---@type string
local plenary = os.getenv("PLENARY_PATH") or (root .. "/deps/plenary.nvim")

vim.env.XDG_STATE_HOME = root .. "/.tmp/state"
vim.fn.mkdir(vim.env.XDG_STATE_HOME, "p")
vim.g.did_load_ftplugin = 1
vim.api.nvim_cmd({ cmd = "filetype", args = { "plugin", "off" } }, {})

-- Disable ShaDa file to prevent test warnings
vim.opt.shadafile = "NONE"

vim.opt.runtimepath = vim.env.VIMRUNTIME
vim.opt.runtimepath:append(root)
vim.opt.runtimepath:append(plenary)
vim.opt.packpath = vim.opt.runtimepath:get()

vim.api.nvim_cmd({ cmd = "runtime", args = { "plugin/plenary.vim" } }, {})
