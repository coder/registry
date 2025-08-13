-- Test Suite for Amazon Q Main Module

local amazonq = require("main.amazon_q_main")
local logger = require("agent_api.utils").logger

-- Test data
local testConfig = {
    region = "us-east-1",
    logLevel = "debug"
}

local testMessage = {
    type = "chat",
    content = {
        message = "Hello, Amazon Q!"
    }
}

-- Test setup
local function setup()
    -- Initialize the module
    local success = amazonq.initialize(testConfig)
    if not success then
        error("Failed to initialize Amazon Q module")
    end
end

-- Test teardown
local function teardown()
    -- Shutdown the module
    amazonq.shutdown()
end

-- Test cases
local tests = {
    testInitialization = function()
        print("Running testInitialization...")
        
        -- Initialize with valid config
        local success = amazonq.initialize(testConfig)
        assert(success, "Initialization should succeed with valid config")
        
        -- Try to initialize again (should fail)
        success = amazonq.initialize(testConfig)
        assert(not success, "Initialization should fail when already initialized")
        
        -- Shutdown
        amazonq.shutdown()
        
        print("testInitialization passed!")
    end,
    
    testChat = function()
        print("Running testChat...")
        
        setup()
        
        -- Send a chat message
        local response, err = amazonq.chat("Test message")
        
        -- In a real test, we would mock the API response
        -- For now, we just check that no error occurred
        assert(not err, "Chat should not return an error: " .. (err or "nil"))
        
        teardown()
        
        print("testChat passed!")
    end,
    
    testGenerateCode = function()
        print("Running testGenerateCode...")
        
        setup()
        
        -- Generate code
        local response, err = amazonq.generateCode("Create a hello world function", "lua")
        
        -- In a real test, we would mock the API response
        -- For now, we just check that no error occurred
        assert(not err, "Code generation should not return an error: " .. (err or "nil"))
        
        teardown()
        
        print("testGenerateCode passed!")
    end,
    
    testTaskManagement = function()
        print("Running testTaskManagement...")
        
        setup()
        
        -- Create a task
        local taskId = amazonq.createTask("Test Task", "This is a test task")
        assert(taskId, "Task creation should return a valid task ID")
        
        -- Update task status
        local success = amazonq.updateTaskStatus(taskId, "running")
        assert(success, "Task status update should succeed")
        
        -- Complete the task
        success = amazonq.updateTaskStatus(taskId, "done")
        assert(success, "Task completion should succeed")
        
        teardown()
        
        print("testTaskManagement passed!")
    end,
    
    testConfiguration = function()
        print("Running testConfiguration...")
        
        -- Configure before initialization
        local success = amazonq.configure({
            region = "us-west-2",
            logLevel = "info"
        })
        assert(success, "Configuration should succeed before initialization")
        
        -- Initialize
        success = amazonq.initialize()
        assert(success, "Initialization should succeed after configuration")
        
        -- Try to configure after initialization (should fail)
        success = amazonq.configure({ region = "us-east-1" })
        assert(not success, "Configuration should fail after initialization")
        
        teardown()
        
        print("testConfiguration passed!")
    end
}

-- Run all tests
local function runTests()
    print("Starting Amazon Q module tests...")
    
    for testName, testFunc in pairs(tests) do
        local success, err = pcall(testFunc)
        
        if not success then
            print("Test failed: " .. testName)
            print("Error: " .. err)
            return false
        end
    end
    
    print("All tests passed!")
    return true
end

-- Run tests if this file is executed directly
if arg and arg[0] == "tests/test_amazon_q.lua" then
    runTests()
end

return tests