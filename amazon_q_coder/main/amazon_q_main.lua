-- Amazon Q Main Runtime for Mudlet
-- Core integration logic for Amazon Q with Mudlet

local amazonq = {}
amazonq.__index = amazonq

-- Dependencies
local sessionHandler = require("agent_api.session_handler")
local coderTasks = require("coder_tasks_api.coder_tasks")
local logger = require("agent_api.utils").logger

-- Module state
local _state = {
    initialized = false,
    sessionId = nil,
    config = {
        region = "us-east-1",
        profile = nil,
        logLevel = "info"
    },
    activeTasks = {}
}

-- Initialize the Amazon Q module
function amazonq.initialize(config)
    if _state.initialized then
        logger:warn("Amazon Q already initialized")
        return false
    end
    
    -- Merge configuration
    if config then
        for k, v in pairs(config) do
            _state.config[k] = v
        end
    end
    
    -- Initialize session handler
    _state.sessionId = sessionHandler.createSession()
    
    -- Initialize coder tasks
    coderTasks.initialize(_state.config)
    
    _state.initialized = true
    logger:info("Amazon Q module initialized")
    return true
end

-- Send a chat message to Amazon Q
function amazonq.chat(message)
    if not _state.initialized then
        logger:error("Amazon Q not initialized")
        return nil, "Not initialized"
    end
    
    logger:debug("Sending chat message to Amazon Q")
    
    -- Create a task for this request
    local taskId = coderTasks.createTask({
        name = "Amazon Q Chat",
        description = "Chat interaction with Amazon Q",
        type = "chat"
    })
    
    -- Update task status to running
    coderTasks.updateTaskStatus(taskId, "running")
    
    -- Send message via session handler
    local response, err = sessionHandler.sendMessage({
        sessionId = _state.sessionId,
        type = "chat",
        content = message,
        taskId = taskId
    })
    
    if err then
        coderTasks.updateTaskStatus(taskId, "error", err)
        return nil, err
    end
    
    -- Update task status to completed
    coderTasks.updateTaskStatus(taskId, "done")
    
    return response
end

-- Generate code with Amazon Q
function amazonq.generateCode(prompt, language)
    if not _state.initialized then
        logger:error("Amazon Q not initialized")
        return nil, "Not initialized"
    end
    
    language = language or "lua"
    logger:debug("Generating code with Amazon Q")
    
    -- Create a task for this request
    local taskId = coderTasks.createTask({
        name = "Code Generation",
        description = "Generate code using Amazon Q",
        type = "code_generation"
    })
    
    -- Update task status to running
    coderTasks.updateTaskStatus(taskId, "running")
    
    -- Send code generation request
    local response, err = sessionHandler.sendMessage({
        sessionId = _state.sessionId,
        type = "code_generation",
        content = {
            prompt = prompt,
            language = language
        },
        taskId = taskId
    })
    
    if err then
        coderTasks.updateTaskStatus(taskId, "error", err)
        return nil, err
    end
    
    -- Update task status to completed
    coderTasks.updateTaskStatus(taskId, "done")
    
    return response
end

-- Create a new task
function amazonq.createTask(name, description)
    if not _state.initialized then
        logger:error("Amazon Q not initialized")
        return nil, "Not initialized"
    end
    
    local taskId = coderTasks.createTask({
        name = name,
        description = description,
        type = "custom"
    })
    
    return taskId
end

-- Update task status
function amazonq.updateTaskStatus(taskId, status, errorMessage)
    if not _state.initialized then
        logger:error("Amazon Q not initialized")
        return false, "Not initialized"
    end
    
    return coderTasks.updateTaskStatus(taskId, status, errorMessage)
end

-- Configure the module
function amazonq.configure(config)
    if _state.initialized then
        logger:warn("Cannot configure after initialization")
        return false
    end
    
    for k, v in pairs(config) do
        _state.config[k] = v
    end
    
    logger:info("Configuration updated")
    return true
end

-- Shutdown the module
function amazonq.shutdown()
    if not _state.initialized then
        return false
    end
    
    sessionHandler.closeSession(_state.sessionId)
    _state.initialized = false
    logger:info("Amazon Q module shutdown")
    return true
end

return amazonq