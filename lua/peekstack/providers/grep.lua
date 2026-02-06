local fs = require("peekstack.util.fs")
local location = require("peekstack.core.location")

local M = {}

---@param line string
---@return string?, integer?, integer?, string?
local function parse_rg_line(line)
  local path, lnum, col, text = line:match("^(.*):(%d+):(%d+):(.*)$")
  if not path then
    return nil, nil, nil, nil
  end
  return path, tonumber(lnum), tonumber(col), text
end

---@param output string
---@return PeekstackLocation[]
local function parse_rg_output(output)
  local items = {}
  for _, line in ipairs(vim.split(output, "\n", { trimempty = true })) do
    local path, lnum, col, text = parse_rg_line(line)
    if path and lnum and col then
      local uri = fs.fname_to_uri(vim.fn.fnamemodify(path, ":p"))
      local loc = location.normalize({
        uri = uri,
        range = {
          start = { line = lnum - 1, character = col - 1 },
          ["end"] = { line = lnum - 1, character = col - 1 },
        },
        text = text,
      }, "grep.search")
      if loc then
        table.insert(items, loc)
      end
    end
  end
  return items
end

---@param _ PeekstackProviderContext
---@param cb fun(locations: PeekstackLocation[])
function M.search(_, cb)
  if vim.fn.executable("rg") ~= 1 then
    vim.notify("rg not found in PATH", vim.log.levels.WARN)
    cb({})
    return
  end

  vim.ui.input({ prompt = "rg > " }, function(query)
    if not query or query == "" then
      cb({})
      return
    end

    vim.system({ "rg", "--vimgrep", query }, { text = true }, function(result)
      vim.schedule(function()
        if result.code ~= 0 and result.code ~= 1 then
          vim.notify("rg failed: " .. (result.stderr or "unknown error"), vim.log.levels.WARN)
          cb({})
          return
        end
        cb(parse_rg_output(result.stdout or ""))
      end)
    end)
  end)
end

---Expose parser for tests.
M._parse_output = parse_rg_output

return M
