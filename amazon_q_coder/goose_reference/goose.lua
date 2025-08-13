-- Goose Module Reference Implementation
-- Provides patterns for integrating with Agent API and Coder Tasks

local goose = {}
goose.__index = goose

-- Dependencies
local sessionHandler = require("agent_api.session_handler")
local coderTasks = require("coder_tasks_api.coder_tasks")
local logger = require("agent_api.utils").logger
local helpers = require("goose_reference.goose_helpers")

-- Module state
local _state = {
    initialized = false,
    sessionId = nil,
    config = {
        logLevel = "info",
        autoStart = true
    },
    activeTasks = {}
}

-- Initialize the Goose module
function goose.initialize(config)
    if _state.initialized then
        logger:warn("Goose module already initialized")
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
    logger:info("Goose module initialized")
    return true
end

-- Process a message with Goose
function goose.processMessage(message)
    if not _state.initialized then
        logger:error("Goose not initialized")
        return nil, "Not initialized"
    end
    
    logger:debug("Processing message with Goose")
    
    -- Create a task for this request
    local taskId = coderTasks.createTask({
        name = "Goose Task: " .. (message.type or "Unknown"),
        description = "Task processed by Goose",
        type = "goose"
    })
    
    -- Update task status to running
    coderTasks.updateTaskStatus(taskId, coderTasks.STATUS.RUNNING)
    
    -- Store task context
    _state.activeTasks[taskId] = {
        message = message,
        startTime = os.time()
    }
    
    -- Process the message based on its type
    local response, err
    if message.type == "chat" then
        response, err = goose.handleChatMessage(message.content)
    elseif message.type == "command" then
        response, err = goose.handleCommand(message.content)
    elseif message.type == "file_operation" then
        response, err = goose.handleFileOperation(message.content)
    else
        response, err = nil, "Unknown message type: " .. (message.type or "nil")
    end
    
    if err then
        coderTasks.updateTaskStatus(taskId, coderTasks.STATUS.ERROR, err)
        _state.activeTasks[taskId] = nil
        return nil, err
    end
    
    -- Update task status to completed
    coderTasks.updateTaskStatus(taskId, coderTasks.STATUS.DONE)
    
    -- Clean up the active task
    _state.activeTasks[taskId] = nil
    
    return response
end

-- Handle a chat message
function goose.handleChatMessage(content)
    logger:debug("Handling chat message")
    
    -- Simulate processing time
    os.execute("sleep 1")
    
    return {
        type = "chat_response",
        content = "Goose response to: " .. (content.message or "empty message"),
        timestamp = os.time()
    }
end

-- Handle a command
function goose.handleCommand(content)
    logger:debug("Handling command")
    
    -- Simulate processing time
    os.execute("sleep 1.5")
    
    return {
        type = "command_result",
        content = {
            command = content.command or "unknown",
            output = "Goose executed command: " .. (content.command or "unknown"),
            exitCode = 0
        },
        timestamp = os.time()
    }
end

-- Handle a file operation
function goose.handleFileOperation(content)
    logger:debug("Handling file operation")
    
    -- Simulate processing time
    os.execute("sleep 0.8")
    
    return {
        type = "file_operation_result",
        content = {
            operation = content.operation or "unknown",
            path = content.path or "unknown",
            success = true,
            message = "Goose performed " .. (content.operation or "unknown") .. " on " .. (content.path or "unknown")
        },
        timestamp = os.time()
    }
end

-- Stream task status updates
function goose.streamTaskStatus(taskId, statusUpdates)
    if not _state.initialized then
        return false, "Not initialized"
    end
    
    return sessionHandler.streamTaskStatus(taskId, statusUpdates)
end

-- Get active tasks
function goose.getActiveTasks()
    local tasks = {}
    
    for taskId, taskData in pairs(_state.activeTasks) do
        local task = coderTasks.getTask(taskId)
        if task then
            table.insert(tasks, task)
        end
    end
    
    return tasks
end

-- Shutdown the Goose module
function goose.shutdown()
    if not _state.initialized then
        return false
    end
    
    sessionHandler.closeSession(_state.sessionId)
    _state.initialized = false
    logger:info("Goose module shutdown")
    return true
end

return goose