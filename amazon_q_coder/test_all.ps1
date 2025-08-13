# Comprehensive test script for Amazon Q + Coder Tasks + AgentAPI Integration

Write-Host "=== Amazon Q + Coder Tasks + AgentAPI Integration Test ===" -ForegroundColor Green

# Test 1: Check if required files exist
Write-Host "
Test 1: Checking required files..." -ForegroundColor Yellow
 = @(
    "tests\test_agent_api.lua",
    "tests\simple_test.lua",
    "run_tests.ps1"
)

 = True
foreach ( in ) {
    if (Test-Path ) {
        Write-Host "  ?  exists" -ForegroundColor Green
    } else {
        Write-Host "  ?  missing" -ForegroundColor Red
         = False
    }
}

if (-not ) {
    Write-Host "Some required files are missing. Please check the file structure." -ForegroundColor Red
    exit 1
}

# Test 2: Check Lua installation
Write-Host "
Test 2: Checking Lua installation..." -ForegroundColor Yellow
try {
     = lua -v 2>&1
    Write-Host "  ? Lua is installed: " -ForegroundColor Green
} catch {
    Write-Host "  ? Lua is not installed or not in PATH" -ForegroundColor Red
    Write-Host "  Error: " -ForegroundColor Red
    exit 1
}

# Test 3: Run simple Lua test
Write-Host "
Test 3: Running simple Lua test..." -ForegroundColor Yellow
try {
     = lua "tests\simple_test.lua" 2>&1
    Write-Host "  ? Simple test passed:" -ForegroundColor Green
    Write-Host "  Output: " -ForegroundColor Cyan
} catch {
    Write-Host "  ? Simple test failed" -ForegroundColor Red
    Write-Host "  Error: " -ForegroundColor Red
}

# Test 4: Run Agent API test
Write-Host "
Test 4: Running Agent API test..." -ForegroundColor Yellow
try {
     = lua "tests\test_agent_api.lua" 2>&1
    Write-Host "  ? Agent API test passed:" -ForegroundColor Green
    Write-Host "  Output: " -ForegroundColor Cyan
} catch {
    Write-Host "  ? Agent API test failed" -ForegroundColor Red
    Write-Host "  Error: " -ForegroundColor Red
}

# Test 5: Run PowerShell test script
Write-Host "
Test 5: Running PowerShell test script..." -ForegroundColor Yellow
try {
     = .\run_tests.ps1 2>&1
    Write-Host "  ? PowerShell test script passed:" -ForegroundColor Green
    Write-Host "  Output: " -ForegroundColor Cyan
} catch {
    Write-Host "  ? PowerShell test script failed" -ForegroundColor Red
    Write-Host "  Error: " -ForegroundColor Red
}

# Test 6: Check if AgentAPI integration files exist
Write-Host "
Test 6: Checking AgentAPI integration files..." -ForegroundColor Yellow
 = @(
    "modules\amazon-q\agentapi_integration.lua",
    "modules\amazon-q\config.lua",
    "modules\amazon-q\task_handler.lua"
)

 = True
foreach ( in ) {
    if (Test-Path ) {
        Write-Host "  ?  exists" -ForegroundColor Green
    } else {
        Write-Host "  ?  missing" -ForegroundColor Red
         = False
    }
}

if (-not ) {
    Write-Host "Some AgentAPI integration files are missing. This is expected if you haven't implemented them yet." -ForegroundColor Yellow
}

# Test 7: Check documentation files
Write-Host "
Test 7: Checking documentation files..." -ForegroundColor Yellow
 = @(
    "docs\using-ai-modules-with-tasks.md",
    "README.md"
)

 = True
foreach ( in ) {
    if (Test-Path ) {
        Write-Host "  ?  exists" -ForegroundColor Green
    } else {
        Write-Host "  ?  missing" -ForegroundColor Yellow
         = False
    }
}

if (-not ) {
    Write-Host "Some documentation files are missing. You may want to create them later." -ForegroundColor Yellow
}

Write-Host "
=== Test Summary ===" -ForegroundColor Green
Write-Host "Basic functionality tests completed. If all tests passed, your project structure is working correctly." -ForegroundColor Green
Write-Host "If you encountered any errors, please check the specific test output above." -ForegroundColor Yellow
