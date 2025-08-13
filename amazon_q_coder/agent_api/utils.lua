-- Utility Functions for Agent API
-- Common helper functions used across the Agent API components

local utils = {}
utils.__index = utils

-- Generate a UUID
function utils.generateUUID()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

-- Logger implementation
utils.logger = {
    debug = function(message)
        if _config and _config.logLevel == "debug" then
            print("[DEBUG] " .. os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message)
        end
    end,
    
    info = function(message)
        print("[INFO] " .. os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message)
    end,
    
    warn = function(message)
        print("[WARN] " .. os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message)
    end,
    
    error = function(message)
        print("[ERROR] " .. os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message)
    end
}

-- Deep copy a table
function utils.deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[utils.deepcopy(orig_key)] = utils.deepcopy(orig_value)
        end
        setmetatable(copy, utils.deepcopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Merge two tables
function utils.mergeTables(t1, t2)
    for k, v in pairs(t2) do
        if (type(v) == "table") and (type(t1[k] or false) == "table") then
            utils.mergeTables(t1[k], t2[k])
        else
            t1[k] = v
        end
    end
    return t1
end

-- Convert a table to a query string
function utils.tableToQueryString(params)
    local queryParts = {}
    
    for k, v in pairs(params) do
        table.insert(queryParts, k .. "=" .. utils.urlEncode(v))
    end
    
    return table.concat(queryParts, "&")
end

-- URL encode a string
function utils.urlEncode(str)
    if str then
        str = string.gsub (str, "\n", "\r\n")
        str = string.gsub (str, "([^%w %-%_%.%~])",
            function (c) return string.format ("%%%02X", string.byte(c)) end)
        str = string.gsub (str, " ", "+")
    end
    return str
end

-- Check if a file exists
function utils.fileExists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    else
        return false
    end
end

-- Read a file
function utils.readFile(path)
    local f = io.open(path, "r")
    if not f then
        return nil, "Could not open file: " .. path
    end
    
    local content = f:read("*a")
    f:close()
    
    return content
end

-- Write to a file
function utils.writeFile(path, content)
    local f = io.open(path, "w")
    if not f then
        return false, "Could not open file for writing: " .. path
    end
    
    f:write(content)
    f:close()
    
    return true
end

-- Get current timestamp
function utils.timestamp()
    return os.time()
end

-- Format timestamp as readable string
function utils.formatTimestamp(timestamp)
    return os.date("%Y-%m-%d %H:%M:%S", timestamp)
end

return utils