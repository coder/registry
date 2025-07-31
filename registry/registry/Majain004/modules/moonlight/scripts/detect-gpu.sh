#!/bin/bash
set -e

# GPU Detection Script for Linux
# Detects NVIDIA GPUs and determines streaming method

echo "Detecting GPU hardware..."

# Check for NVIDIA GPUs
if command -v lspci &> /dev/null; then
    nvidia_gpus=$(lspci | grep -i nvidia)
    
    if [ -n "$nvidia_gpus" ]; then
        echo "NVIDIA GPU detected:"
        echo "$nvidia_gpus"
        
        # Check if nvidia-smi is available
        if command -v nvidia-smi &> /dev/null; then
            echo "NVIDIA drivers found - GameStream available"
            streaming_method="gamestream"
        else
            echo "NVIDIA drivers not found - using Sunshine"
            streaming_method="sunshine"
        fi
    else
        echo "No NVIDIA GPU detected - using Sunshine"
        streaming_method="sunshine"
    fi
else
    echo "lspci not available - using Sunshine"
    streaming_method="sunshine"
fi

# Output the streaming method for the main script
echo "STREAMING_METHOD=$streaming_method"
echo "GPU detection completed successfully" 