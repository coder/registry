# Simple test script to verify basic functionality

Write-Host "=== Basic Functionality Test ===" -ForegroundColor Green

# Test 1: Check if test files exist
Write-Host "
Test 1: Checking test files..." -ForegroundColor Yellow
if (Test-Path "tests\simple_test.lua") {
    Write-Host "  ? simple_test.lua exists" -ForegroundColor Green
} else {
    Write-Host "  ? simple_test.lua missing" -ForegroundColor Red
}

if (Test-Path "tests\test_agent_api.lua") {
    Write-Host "  ? test_agent_api.lua exists" -ForegroundColor Green
} else {
    Write-Host "  ? test_agent_api.lua missing" -ForegroundColor Red
}

# Test 2: Check Lua installation
Write-Host "
Test 2: Checking Lua installation..." -ForegroundColor Yellow
try {
     = lua -v 2>&1
    Write-Host "  ? Lua is installed: " -ForegroundColor Green
} catch {
    Write-Host "  ? Lua is not installed or not in PATH" -ForegroundColor Red
}

# Test 3: Run simple Lua test
Write-Host "
Test 3: Running simple Lua test..." -ForegroundColor Yellow
if (Test-Path "tests\simple_test.lua") {
    try {
         = lua "tests\simple_test.lua" 2>&1
        Write-Host "  ? Simple test output:" -ForegroundColor Green
        Write-Host "  " -ForegroundColor Cyan
    } catch {
        Write-Host "  ? Simple test failed" -ForegroundColor Red
    }
} else {
    Write-Host "  ? Cannot run test - file missing" -ForegroundColor Red
}

# Test 4: Run Agent API test
Write-Host "
Test 4: Running Agent API test..." -ForegroundColor Yellow
if (Test-Path "tests\test_agent_api.lua") {
    try {
         = lua "tests\test_agent_api.lua" 2>&1
        Write-Host "  ? Agent API test output:" -ForegroundColor Green
        Write-Host "  " -ForegroundColor Cyan
    } catch {
        Write-Host "  ? Agent API test failed" -ForegroundColor Red
    }
} else {
    Write-Host "  ? Cannot run test - file missing" -ForegroundColor Red
}

Write-Host "
=== Test Complete ===" -ForegroundColor Green
