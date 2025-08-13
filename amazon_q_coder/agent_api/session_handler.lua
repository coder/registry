-- Agent API Session Handler for Amazon Q
-- Manages sessions and message passing with the Agent API

local sessionHandler = {}
sessionHandler.__index = sessionHandler

local logger = require("agent_api.utils").logger
local apiRequests = require("agent_api.api_requests")
local utils = require("agent_api.utils")

-- Active sessions
local _sessions = {}

-- Create a new session
function sessionHandler.createSession()
    local sessionId = utils.generateUUID()
    
    _sessions[sessionId] = {
        id = sessionId,
        created = os.time(),
        lastActivity = os.time(),
        status = "active",
        messageQueue = {}
    }
    
    logger:debug("Created new session: " .. sessionId)
    return sessionId
end

-- Close a session
function sessionHandler.closeSession(sessionId)
    if not _sessions[sessionId] then
        logger:warn("Attempted to close non-existent session: " .. sessionId)
        return false
    end
    
    _sessions[sessionId].status = "closed"
    _sessions[sessionId].closedAt = os.time()
    
    logger:debug("Closed session: " .. sessionId)
    return true
end

-- Send a message through the session
function sessionHandler.sendMessage(message)
    local sessionId = message.sessionId
    
    if not _sessions[sessionId] then
        return nil, "Session not found: " .. (sessionId or "nil")
    end
    
    if _sessions[sessionId].status ~= "active" then
        return nil, "Session is not active: " .. sessionId
    end
    
    -- Update last activity
    _sessions[sessionId].lastActivity = os.time()
    
    -- Add timestamp if not present
    if not message.timestamp then
        message.timestamp = os.time()
    end
    
    logger:debug("Sending message via session " .. sessionId)
    
    -- Send via API requests
    local response, err = apiRequests.sendToAgentAPI(message)
    
    if err then
        logger:error("Failed to send message: " .. err)
        return nil, err
    end
    
    return response
end

-- Stream task status updates
function sessionHandler.streamTaskStatus(taskId, statusUpdates)
    logger:debug("Streaming status updates for task: " .. taskId)
    
    for _, update in ipairs(statusUpdates) do
        local message = {
            type = "task_update",
            taskId = taskId,
            content = {
                status = update.status,
                message = update.message,
                progress = update.progress or 0
            },
            timestamp = os.time()
        }
        
        local _, err = apiRequests.sendToAgentAPI(message)
        
        if err then
            logger:error("Failed to stream status update: " .. err)
            return false, err
        end
        
        -- Small delay between updates
        os.execute("sleep 0.1")
    end
    
    return true
end

-- Get session information
function sessionHandler.getSessionInfo(sessionId)
    return _sessions[sessionId]
end

-- Get all active sessions
function sessionHandler.getActiveSessions()
    local active = {}
    
    for id, session in pairs(_sessions) do
        if session.status == "active" then
            table.insert(active, session)
        end
    end
    
    return active
end

-- Clean up inactive sessions
function sessionHandler.cleanupSessions(maxAge)
    maxAge = maxAge or 3600 -- Default: 1 hour
    
    local now = os.time()
    local cleaned = 0
    
    for id, session in pairs(_sessions) do
        if session.status == "active" and (now - session.lastActivity) > maxAge then
            sessionHandler.closeSession(id)
            cleaned = cleaned + 1
        end
    end
    
    if cleaned > 0 then
        logger:info("Cleaned up " .. cleaned .. " inactive sessions")
    end
    
    return cleaned
end

return sessionHandler