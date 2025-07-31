# GPU Detection Script for Windows
# Detects NVIDIA GPUs and determines streaming method

Write-Host "Detecting GPU hardware..."

# Get all video controllers
$videoControllers = Get-WmiObject -Class Win32_VideoController

# Look for NVIDIA GPUs
$nvidiaGPUs = $videoControllers | Where-Object {$_.Name -like "*NVIDIA*"}

if ($nvidiaGPUs) {
    Write-Host "NVIDIA GPU detected:"
    foreach ($gpu in $nvidiaGPUs) {
        Write-Host "  - $($gpu.Name)"
        Write-Host "    Memory: $([math]::Round($gpu.AdapterRAM / 1GB, 2)) GB"
    }
    
    # Check if GeForce Experience is installed
    $geForcePath = "${env:ProgramFiles}\NVIDIA Corporation\NVIDIA GeForce Experience"
    if (Test-Path $geForcePath) {
        Write-Host "GeForce Experience found - GameStream available"
        $streamingMethod = "gamestream"
    } else {
        Write-Host "GeForce Experience not found - using Sunshine"
        $streamingMethod = "sunshine"
    }
} else {
    Write-Host "No NVIDIA GPU detected - using Sunshine"
    $streamingMethod = "sunshine"
}

# Output the streaming method for the main script
Write-Host "STREAMING_METHOD=$streamingMethod"
Write-Host "GPU detection completed successfully" 