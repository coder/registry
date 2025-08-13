-- Helper Functions for Goose Module
-- Common helper functions used across the Goose module

local helpers = {}
helpers.__index = helpers

local logger = require("agent_api.utils").logger

-- Format a timestamp for display
function helpers.formatTimestamp(timestamp)
    if not timestamp then
        return "N/A"
    end
    
    return os.date("%Y-%m-%d %H:%M:%S", timestamp)
end

-- Calculate task duration
function helpers.calculateTaskDuration(task)
    if not task or not task.started then
        return 0
    end
    
    local endTime = task.completed or os.time()
    return endTime - task.started
end

-- Format duration in human-readable format
function helpers.formatDuration(seconds)
    if seconds < 60 then
        return string.format("%d seconds", seconds)
    elseif seconds < 3600 then
        return string.format("%d minutes, %d seconds", math.floor(seconds / 60), seconds % 60)
    else
        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        return string.format("%d hours, %d minutes", hours, minutes)
    end
end

-- Truncate a string to a maximum length
function helpers.truncate(str, maxLength)
    if not str then
        return ""
    end
    
    if #str <= maxLength then
        return str
    end
    
    return str:sub(1, maxLength - 3) .. "..."
end

-- Escape special characters for regex
function helpers.escapeRegex(str)
    return str:gsub("([^%w])", "%%%1")
end

-- Generate a simple progress bar
function helpers.progressBar(progress, width)
    width = width or 20
    progress = math.max(0, math.min(100, progress))
    
    local filled = math.floor(width * progress / 100)
    local bar = string.rep("=", filled) .. string.rep(" ", width - filled)
    
    return string.format("[%s] %d%%", bar, progress)
end

-- Sanitize a string for safe display
function helpers.sanitize(str)
    if not str then
        return ""
    end
    
    -- Replace control characters with spaces
    str = str:gsub("%c", " ")
    
    -- Trim leading/trailing whitespace
    str = str:match("^%s*(.-)%s*$") or ""
    
    return str
end

-- Parse a key-value pair string
function helpers.parseKeyValue(str, delimiter, separator)
    delimiter = delimiter or "="
    separator = separator or "&"
    
    local result = {}
    
    for pair in str:gmatch("([^" .. separator .. "]+)") do
        local key, value = pair:match("([^" .. delimiter .. "]+)" .. delimiter .. "(.*)")
        
        if key and value then
            result[key] = value
        end
    end
    
    return result
end

-- Convert a table to a string representation
function helpers.tableToString(tbl, indent)
    indent = indent or 0
    local indentStr = string.rep("  ", indent)
    
    if type(tbl) ~= "table" then
        return tostring(tbl)
    end
    
    local result = "{\n"
    
    for k, v in pairs(tbl) do
        result = result .. indentStr .. "  "
        
        if type(k) == "string" then
            result = result .. k .. " = "
        else
            result = result .. "[" .. k .. "] = "
        end
        
        if type(v) == "table" then
            result = result .. helpers.tableToString(v, indent + 1)
        else
            result = result .. tostring(v)
        end
        
        result = result .. ",\n"
    end
    
    result = result .. indentStr .. "}"
    return result
end

-- Merge two tables recursively
function helpers.mergeTables(t1, t2)
    for k, v in pairs(t2) do
        if type(v) == "table" and type(t1[k]) == "table" then
            helpers.mergeTables(t1[k], v)
        else
            t1[k] = v
        end
    end
    
    return t1
end

-- Check if a table contains a value
function helpers.tableContains(tbl, value)
    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    
    return false
end

-- Get the keys of a table
function helpers.tableKeys(tbl)
    local keys = {}
    
    for k, _ in pairs(tbl) do
        table.insert(keys, k)
    end
    
    return keys
end

-- Get the values of a table
function helpers.tableValues(tbl)
    local values = {}
    
    for _, v in pairs(tbl) do
        table.insert(values, v)
    end
    
    return values
end

return helpers