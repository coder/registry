-- Coder Tasks API for Amazon Q
-- Manages tasks and their lifecycle

local coderTasks = {}
coderTasks.__index = coderTasks

local logger = require("agent_api.utils").logger
local utils = require("agent_api.utils")

-- Task status constants
local TASK_STATUS = {
    PENDING = "pending",
    RUNNING = "running",
    DONE = "done",
    ERROR = "error"
}

-- Active tasks
local _tasks = {}
local _config = {}

-- Initialize the Coder Tasks API
function coderTasks.initialize(config)
    _config = config or {}
    logger:info("Coder Tasks API initialized")
end

-- Create a new task
function coderTasks.createTask(taskData)
    local taskId = utils.generateUUID()
    
    local task = {
        id = taskId,
        name = taskData.name or "Unnamed Task",
        description = taskData.description or "",
        status = taskData.status or TASK_STATUS.PENDING,
        type = taskData.type or "generic",
        created = os.time(),
        metadata = taskData.metadata or {}
    }
    
    _tasks[taskId] = task
    
    logger:debug("Created task: " .. taskId .. " - " .. task.name)
    return taskId
end

-- Get a task by ID
function coderTasks.getTask(taskId)
    return _tasks[taskId]
end

-- Update a task
function coderTasks.updateTask(taskId, updates)
    local task = _tasks[taskId]
    
    if not task then
        return false, "Task not found: " .. taskId
    end
    
    -- Apply updates
    for k, v in pairs(updates) do
        task[k] = v
    end
    
    logger:debug("Updated task: " .. taskId)
    return true
end

-- Update task status with validation
function coderTasks.updateTaskStatus(taskId, status, errorMessage)
    local task = _tasks[taskId]
    
    if not task then
        return false, "Task not found: " .. taskId
    end
    
    -- Validate status transition
    if not coderTasks.isValidStatusTransition(task.status, status) then
        return false, "Invalid status transition from " .. task.status .. " to " .. status
    end
    
    -- Update status
    task.status = status
    
    -- Set timestamps based on status
    if status == TASK_STATUS.RUNNING and not task.started then
        task.started = os.time()
    elseif (status == TASK_STATUS.DONE or status == TASK_STATUS.ERROR) and not task.completed then
        task.completed = os.time()
    end
    
    -- Store error message if provided
    if status == TASK_STATUS.ERROR and errorMessage then
        task.errorMessage = errorMessage
    end
    
    logger:debug("Updated task status: " .. taskId .. " -> " .. status)
    return true
end

-- Validate status transition
function coderTasks.isValidStatusTransition(fromStatus, toStatus)
    local validTransitions = {
        [TASK_STATUS.PENDING] = {TASK_STATUS.RUNNING, TASK_STATUS.ERROR},
        [TASK_STATUS.RUNNING] = {TASK_STATUS.DONE, TASK_STATUS.ERROR},
        [TASK_STATUS.DONE] = {},
        [TASK_STATUS.ERROR] = {TASK_STATUS.RUNNING}  -- Allow retry after error
    }
    
    local allowed = validTransitions[fromStatus] or {}
    
    for _, status in ipairs(allowed) do
        if status == toStatus then
            return true
        end
    end
    
    return false
end

-- Delete a task
function coderTasks.deleteTask(taskId)
    if not _tasks[taskId] then
        return false, "Task not found: " .. taskId
    end
    
    _tasks[taskId] = nil
    logger:debug("Deleted task: " .. taskId)
    return true
end

-- List tasks with optional filtering
function coderTasks.listTasks(filter)
    filter = filter or {}
    local result = {}
    
    for taskId, task in pairs(_tasks) do
        local include = true
        
        -- Apply status filter
        if filter.status and task.status ~= filter.status then
            include = false
        end
        
        -- Apply type filter
        if filter.type and task.type ~= filter.type then
            include = false
        end
        
        if include then
            table.insert(result, task)
        end
    end
    
    -- Apply sorting (by creation time, newest first)
    table.sort(result, function(a, b)
        return a.created > b.created
    end)
    
    -- Apply pagination
    if filter.offset then
        local offset = math.max(1, filter.offset)
        local paginated = {}
        
        for i = offset, #result do
            table.insert(paginated, result[i])
            
            if filter.limit and #paginated >= filter.limit then
                break
            end
        end
        
        result = paginated
    elseif filter.limit then
        local limited = {}
        
        for i = 1, math.min(filter.limit, #result) do
            table.insert(limited, result[i])
        end
        
        result = limited
    end
    
    return result
end

-- Get task statistics
function coderTasks.getStats()
    local stats = {
        total = 0,
        pending = 0,
        running = 0,
        done = 0,
        error = 0
    }
    
    for _, task in pairs(_tasks) do
        stats.total = stats.total + 1
        
        if task.status == TASK_STATUS.PENDING then
            stats.pending = stats.pending + 1
        elseif task.status == TASK_STATUS.RUNNING then
            stats.running = stats.running + 1
        elseif task.status == TASK_STATUS.DONE then
            stats.done = stats.done + 1
        elseif task.status == TASK_STATUS.ERROR then
            stats.error = stats.error + 1
        end
    end
    
    return stats
end

-- Clean up old tasks
function coderTasks.cleanup(maxAge)
    maxAge = maxAge or 86400 -- Default: 24 hours
    
    local now = os.time()
    local cleaned = 0
    
    for taskId, task in pairs(_tasks) do
        local age = now - task.created
        
        if age > maxAge and (task.status == TASK_STATUS.DONE or task.status == TASK_STATUS.ERROR) then
            _tasks[taskId] = nil
            cleaned = cleaned + 1
        end
    end
    
    if cleaned > 0 then
        logger:info("Cleaned up " .. cleaned .. " old tasks")
    end
    
    return cleaned
end

-- Export status constants
coderTasks.STATUS = TASK_STATUS

return coderTasks