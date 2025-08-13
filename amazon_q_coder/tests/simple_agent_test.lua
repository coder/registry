-- Simple Agent API test
print("=== Simple Agent API Test ===")

-- Create AgentAPI table first
local AgentAPI = {}

-- Then add properties
AgentAPI.initialized = false
AgentAPI.connected = false

-- Then add methods
function AgentAPI.init(config)
    print("Initializing Agent API...")
    AgentAPI.initialized = true
    return true
end

function AgentAPI.connect()
    print("Connecting to Agent API...")
    AgentAPI.connected = true
    return true
end

function AgentAPI.disconnect()
    print("Disconnecting from Agent API...")
    AgentAPI.connected = false
    return true
end

-- Test the functions
print("Running tests...")

-- Test initialization
local success = AgentAPI.init({})
assert(success, "Initialization failed")

-- Test connection
success = AgentAPI.connect()
assert(success, "Connection failed")

-- Test disconnection
success = AgentAPI.disconnect()
assert(success, "Disconnection failed")

print("All tests passed!")
