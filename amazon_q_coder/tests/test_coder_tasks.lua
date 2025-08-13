-- Test Suite for Coder Tasks API

local coderTasks = require("coder_tasks_api.coder_tasks")
local logger = require("agent_api.utils").logger

-- Test data
local testTaskData = {
    name = "Test Task",
    description = "This is a test task",
    type = "test",
    metadata = {
        test = true
    }
}

-- Test setup
local function setup()
    -- Initialize the coder tasks API
    coderTasks.initialize()
end

-- Test teardown
local function teardown()
    -- Clean up all tasks
    for taskId, _ in pairs(coderTasks.listTasks()) do
        coderTasks.deleteTask(taskId)
    end
end

-- Test cases
local tests = {
    testTaskCreation = function()
        print("Running testTaskCreation...")
        
        setup()
        
        -- Create a task
        local taskId = coderTasks.createTask(testTaskData)
        assert(taskId, "Task creation should return a valid task ID")
        
        -- Verify task exists
        local task = coderTasks.getTask(taskId)
        assert(task, "Task should exist")
        assert(task.id == taskId, "Task ID should match")
        assert(task.name == testTaskData.name, "Task name should match")
        assert(task.status == coderTasks.STATUS.PENDING, "Task should be in pending status")
        
        teardown()
        
        print("testTaskCreation passed!")
    end,
    
    testTaskUpdates = function()
        print("Running testTaskUpdates...")
        
        setup()
        
        -- Create a task
        local taskId = coderTasks.createTask(testTaskData)
        
        -- Update task
        local success = coderTasks.updateTask(taskId, {
            name = "Updated Task Name",
            metadata = {
                updated = true
            }
        })
        assert(success, "Task update should succeed")
        
        -- Verify updates
        local task = coderTasks.getTask(taskId)
        assert(task.name == "Updated Task Name", "Task name should be updated")
        assert(task.metadata.updated, "Metadata should be updated")
        
        teardown()
        
        print("testTaskUpdates passed!")
    end,
    
    testStatusTransitions = function()
        print("Running testStatusTransitions...")
        
        setup()
        
        -- Create a task
        local taskId = coderTasks.createTask(testTaskData)
        
        -- Valid transition: pending -> running
        local success = coderTasks.updateTaskStatus(taskId, coderTasks.STATUS.RUNNING)
        assert(success, "Pending to running transition should succeed")
        
        -- Valid transition: running -> done
        success = coderTasks.updateTaskStatus(taskId, coderTasks.STATUS.DONE)
        assert(success, "Running to done transition should succeed")
        
        -- Invalid transition: done -> running
        success = coderTasks.updateTaskStatus(taskId, coderTasks.STATUS.RUNNING)
        assert(not success, "Done to running transition should fail")
        
        -- Create another task for error testing
        local taskId2 = coderTasks.createTask(testTaskData)
        
        -- Valid transition: pending -> error
        success = coderTasks.updateTaskStatus(taskId2, coderTasks.STATUS.ERROR, "Test error")
        assert(success, "Pending to error transition should succeed")
        
        -- Valid transition: error -> running (retry)
        success = coderTasks.updateTaskStatus(taskId2, coderTasks.STATUS.RUNNING)
        assert(success, "Error to running transition should succeed")
        
        teardown()
        
        print("testStatusTransitions passed!")
    end,
    
    testTaskListing = function()
        print("Running testTaskListing...")
        
        setup()
        
        -- Create multiple tasks
        local taskIds = {}
        for i = 1, 10 do
            local taskData = {
                name = "Test Task " .. i,
                description = "This is test task " .. i,
                type = i % 2 == 0 and "even" or "odd"
            }
            table.insert(taskIds, coderTasks.createTask(taskData))
        end
        
        -- List all tasks
        local allTasks = coderTasks.listTasks()
        assert(#allTasks == 10, "Should have 10 tasks")
        
        -- Filter by status
        local pendingTasks = coderTasks.listTasks({status = coderTasks.STATUS.PENDING})
        assert(#pendingTasks == 10, "All tasks should be pending")
        
        -- Filter by type
        local evenTasks = coderTasks.listTasks({type = "even"})
        assert(#evenTasks == 5, "Should have 5 even tasks")
        
        -- Test pagination
        local page1 = coderTasks.listTasks({limit = 5})
        assert(#page1 == 5, "First page should have 5 tasks")
        
        local page2 = coderTasks.listTasks({offset = 5, limit = 5})
        assert(#page2 == 5, "Second page should have 5 tasks")
        
        -- Verify pagination results are different
        local page1Ids = {}
        for _, task in ipairs(page1) do
            table.insert(page1Ids, task.id)
        end
        
        for _, task in ipairs(page2) do
            assert(not coderTasks.tableContains(page1Ids, task.id), "Page 2 should not contain tasks from page 1")
        end
        
        teardown()
        
        print("testTaskListing passed!")
    end,
    
    testTaskStats = function()
        print("Running testTaskStats...")
        
        setup()
        
        -- Create tasks with different statuses
        coderTasks.createTask({name = "Pending Task"})
        local runningId = coderTasks.createTask({name = "Running Task"})
        coderTasks.updateTaskStatus(runningId, coderTasks.STATUS.RUNNING)
        
        local doneId = coderTasks.createTask({name = "Done Task"})
        coderTasks.updateTaskStatus(doneId, coderTasks.STATUS.RUNNING)
        coderTasks.updateTaskStatus(doneId, coderTasks.STATUS.DONE)
        
        local errorId = coderTasks.createTask({name = "Error Task"})
        coderTasks.updateTaskStatus(errorId, coderTasks.STATUS.ERROR)
        
        -- Get stats
        local stats = coderTasks.getStats()
        assert(stats.total == 4, "Should have 4 total tasks")
        assert(stats.pending == 1, "Should have 1 pending task")
        assert(stats.running == 1, "Should have 1 running task")
        assert(stats.done == 1, "Should have 1 done task")
        assert(stats.error == 1, "Should have 1 error task")
        
        teardown()
        
        print("testTaskStats passed!")
    end,
    
    testTaskCleanup = function()
        print("Running testTaskCleanup...")
        
        setup()
        
        -- Create tasks
        local taskIds = {}
        for i = 1, 5 do
            table.insert(taskIds, coderTasks.createTask({
                name = "Task " .. i,
                type = "test"
            }))
        end
        
        -- Complete some tasks
        coderTasks.updateTaskStatus(taskIds[1], coderTasks.STATUS.RUNNING)
        coderTasks.updateTaskStatus(taskIds[1], coderTasks.STATUS.DONE)
        
        coderTasks.updateTaskStatus(taskIds[2], coderTasks.STATUS.RUNNING)
        coderTasks.updateTaskStatus(taskIds[2], coderTasks.STATUS.ERROR)
        
        -- Verify all tasks exist
        assert(#coderTasks.listTasks() == 5, "Should have 5 tasks")
        
        -- Clean up tasks with max age of 0 seconds
        local cleaned = coderTasks.cleanup(0)
        assert(cleaned == 2, "Should have cleaned up 2 completed/errored tasks")
        
        -- Verify remaining tasks
        assert(#coderTasks.listTasks() == 3, "Should have 3 remaining tasks")
        
        teardown()
        
        print("testTaskCleanup passed!")
    end
}

-- Run all tests
local function runTests()
    print("Starting Coder Tasks API tests...")
    
    for testName, testFunc in pairs(tests) do
        local success, err = pcall(testFunc)
        
        if not success then
            print("Test failed: " .. testName)
            print("Error: " .. err)
            return false
        end
    end
    
    print("All Coder Tasks API tests passed!")
    return true
end

-- Run tests if this file is executed directly
if arg and arg[0] == "tests/test_coder_tasks.lua" then
    runTests()
end

return tests