# Test if the test file exists
$testPath = "D:\open source projects\Amazon Q coder\tests\test_agent_api.lua"
if (-not (Test-Path $testPath)) {
    Write-Error "Test file not found: $testPath"
    exit 1
}

# Run the test
Write-Host "Running test: $testPath"
lua $testPath

# Check exit code
if ($LASTEXITCODE -ne 0) {
    Write-Error "Test failed with exit code: $LASTEXITCODE"
    exit $LASTEXITCODE
} else {
    Write-Host "Test completed successfully"
}
