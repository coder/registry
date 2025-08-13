-- Comprehensive Agent API test
print("=== Agent API Integration Test ===")

-- Mock Agent API module
local AgentAPI = {
    initialized = false,
    connected = false
}

-- Define methods after the table is created
function AgentAPI.init(config)
    print("Initializing Agent API with config:")
    for k, v in pairs(config) do
        print("  " .. k .. ": " .. tostring(v))
    end
    AgentAPI.initialized = true
    return true
end

function AgentAPI.connect()
    if not AgentAPI.initialized then
        return false, "Agent API not initialized"
    end
    print("Connecting to Agent API server...")
    AgentAPI.connected = true
    return true
end

function AgentAPI.sendTask(task)
    if not AgentAPI.connected then
        return false, "Not connected to Agent API"
    end
    print("Sending task: " .. task.type)
    print("  Description: " .. task.description)
    return true, "Task accepted"
end

function AgentAPI.getStatus(taskId)
    print("Getting status for task: " .. taskId)
    return "processing", 50, "Analyzing request..."
end

function AgentAPI.getResult(taskId)
    print("Getting result for task: " .. taskId)
    return {
        status = "completed",
        result = "Task completed successfully",
        output = "This is a mock result from Agent API"
    }
end

function AgentAPI.disconnect()
    print("Disconnecting from Agent API...")
    AgentAPI.connected = false
    return true
end

-- Test functions
local function test_initialization()
    print("\n--- Testing Initialization ---")
    local config = {
        endpoint = "https://api.example.com/agent",
        apiKey = "test-key",
        timeout = 30
    }
    local success, err = AgentAPI.init(config)
    assert(success, "Initialization failed: " .. tostring(err))
    print("Initialization test passed!")
end

local function test_connection()
    print("\n--- Testing Connection ---")
    local success, err = AgentAPI.connect()
    assert(success, "Connection failed: " .. tostring(err))
    print("Connection test passed!")
end

local function test_task_sending()
    print("\n--- Testing Task Sending ---")
    local task = {
        type = "coding",
        description = "Create a function to calculate factorial",
        language = "lua"
    }
    local success, message = AgentAPI.sendTask(task)
    assert(success, "Task sending failed: " .. tostring(message))
    print("Task sending test passed!")
end

local function test_status_checking()
    print("\n--- Testing Status Checking ---")
    local status, progress, message = AgentAPI.getStatus("task-123")
    assert(status, "Status check failed")
    print("Status check test passed!")
    print("  Status: " .. status)
    print("  Progress: " .. progress .. "%")
    print("  Message: " .. message)
end

local function test_result_retrieval()
    print("\n--- Testing Result Retrieval ---")
    local result = AgentAPI.getResult("task-123")
    assert(result, "Result retrieval failed")
    print("Result retrieval test passed!")
    print("  Status: " .. result.status)
    print("  Output: " .. result.output)
end

local function test_disconnection()
    print("\n--- Testing Disconnection ---")
    local success = AgentAPI.disconnect()
    assert(success, "Disconnection failed")
    print("Disconnection test passed!")
end

-- Run all tests
local function run_all_tests()
    local tests = {
        test_initialization,
        test_connection,
        test_task_sending,
        test_status_checking,
        test_result_retrieval,
        test_disconnection
    }
    
    print("Running " .. #tests .. " tests...")
    
    for i, test in ipairs(tests) do
        local success, err = pcall(test)
        if not success then
            print("Test " .. i .. " failed: " .. tostring(err))
            return false
        end
    end
    
    print("\n=== All tests passed! ===")
    return true
end

-- Execute tests
local success = run_all_tests()
if not success then
    os.exit(1)
end
