local notify = require("peekstack.util.notify")

local M = {}

-- Subtrees keyed by user-defined names (provider names, filetypes) rather than
-- a fixed schema. Unknown-key detection must not descend into these.
---@type table<string, boolean>
local OPEN_PATHS = {
  ["ui.title.icons.map"] = true,
  ["ui.title.context.node_types"] = true,
}

---@param defaults table
---@return boolean True when the table is a fixed record (not a list/array).
local function is_record(defaults)
  return not vim.islist(defaults) and next(defaults) ~= nil
end

---@param defaults table
---@return string[] Sorted known keys at this level.
local function known_keys_of(defaults)
  local keys = {}
  for key in pairs(defaults) do
    keys[#keys + 1] = tostring(key)
  end
  table.sort(keys)
  return keys
end

---@param section table Merged config subtree.
---@param defaults table Default schema subtree.
---@param prefix string Dotted path of this subtree ("" at the root).
local function walk(section, defaults, prefix)
  for key, value in pairs(section) do
    local path = prefix == "" and tostring(key) or (prefix .. "." .. tostring(key))
    if defaults[key] == nil then
      notify.warn(
        string.format(
          "Unknown config key %q (ignored). Known keys: %s",
          path,
          table.concat(known_keys_of(defaults), ", ")
        )
      )
    elseif
      type(value) == "table"
      and type(defaults[key]) == "table"
      and is_record(defaults[key])
      and not OPEN_PATHS[path]
    then
      walk(value, defaults[key], path)
    end
  end
end

---Warn about unknown/typo'd config keys (e.g. `ui.popups` instead of
---`ui.popup`). Compares the merged config against the default schema and
---reports keys the user supplied that peekstack does not recognise.
---@param cfg table Merged config.
---@param defaults PeekstackConfig
function M.detect(cfg, defaults)
  walk(cfg, defaults, "")
end

return M
