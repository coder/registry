-- Agent API Requests for Amazon Q
-- Handles HTTP requests to the Agent API

local apiRequests = {}
apiRequests.__index = apiRequests

local logger = require("agent_api.utils").logger

-- API configuration
local _config = {
    baseUrl = "http://localhost:8080/api/v1",
    timeout = 30,
    retries = 3
}

-- Configure the API client
function apiRequests.configure(config)
    for k, v in pairs(config) do
        _config[k] = v
    end
    
    logger:info("API configuration updated")
end

-- Send a message to the Agent API
function apiRequests.sendToAgentAPI(message)
    local url = _config.baseUrl .. "/messages"
    local payload = json.encode(message)
    
    logger:debug("Sending message to Agent API: " .. url)
    
    local response, err = apiRequests.httpRequest("POST", url, payload)
    
    if err then
        logger:error("Failed to send message to Agent API: " .. err)
        return nil, err
    end
    
    return json.decode(response)
end

-- Get session information
function apiRequests.getSessionInfo(sessionId)
    local url = _config.baseUrl .. "/sessions/" .. sessionId
    
    logger:debug("Getting session info: " .. url)
    
    local response, err = apiRequests.httpRequest("GET", url)
    
    if err then
        logger:error("Failed to get session info: " .. err)
        return nil, err
    end
    
    return json.decode(response)
end

-- Make an HTTP request
function apiRequests.httpRequest(method, url, payload)
    local cmd = "curl -s -X " .. method .. " "
    
    if payload then
        cmd = cmd .. "-H 'Content-Type: application/json' -d '" .. payload .. "' "
    end
    
    cmd = cmd .. "--max-time " .. _config.timeout .. " "
    cmd = cmd .. "'" .. url .. "'"
    
    local lastErr = nil
    
    for attempt = 1, _config.retries do
        logger:debug("HTTP request attempt " .. attempt .. ": " .. url)
        
        local handle = io.popen(cmd)
        local response = handle:read("*a")
        local success, exitReason = handle:close()
        
        if success then
            return response
        else
            lastErr = exitReason or "Unknown error"
            logger:warn("HTTP request failed: " .. lastErr)
            
            -- Wait before retrying
            if attempt < _config.retries then
                os.execute("sleep " .. (2 ^ attempt))
            end
        end
    end
    
    return nil, lastErr or "Request failed after " .. _config.retries .. " attempts"
end

-- Stream task status updates
function apiRequests.streamTaskUpdates(taskId, updates)
    local url = _config.baseUrl .. "/tasks/" .. taskId .. "/updates"
    
    logger:debug("Streaming task updates: " .. url)
    
    for _, update in ipairs(updates) do
        local payload = json.encode(update)
        local _, err = apiRequests.httpRequest("POST", url, payload)
        
        if err then
            logger:error("Failed to stream task update: " .. err)
            return false, err
        end
        
        -- Small delay between updates
        os.execute("sleep 0.1")
    end
    
    return true
end

return apiRequests